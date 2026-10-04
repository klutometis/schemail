#!/usr/bin/env python3
"""Score the classifier against Peter's own behaviour, not against eyeballs.

Ground truth is free: an inbound email Peter later replied to or forwarded
was signal. So:

  recall     fraction of replied-to emails a method keeps in the inbox
             (the error that matters: signal buried)
  keep rate  fraction of a random sample of recent inbound mail it keeps
             (the inbox burden; ~70 arrive a day)

Methods: the LLM prompts below, plus free header baselines on the same
messages, so the LLM has to beat something that costs nothing.

"Peter has emailed this sender before" is computed as of each message's date
(in:sent to:X before:T); asking it today would leak his reply into the test.

    zsh -c 'source ~/.zshenv; python3 eval/replied_recall.py'   # from repo root

Needs ANTHROPIC_API_KEY and ~/.oauth2.rkt (same grant as the daemon).
Everything is cached in $TMPDIR/schemail-eval, so reruns cost only the
prompts that changed. Cost: roughly $0.003 per message per prompt (Haiku).
"""
import json, os, random, re, subprocess, sys, time, urllib.error, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CACHE = Path(os.environ.get('TMPDIR', '/tmp')) / 'schemail-eval'
CACHE.mkdir(parents=True, exist_ok=True)
N_REPLIED, N_RANDOM, DAYS_REPLIED, DAYS_RANDOM = 500, 400, 365, 30
MODEL = 'claude-haiku-4-5'
HEADERS = ['From', 'To', 'Cc', 'Subject', 'Date', 'List-Unsubscribe', 'List-Id',
           'Precedence', 'Auto-Submitted']
random.seed(20261004)

# ---------------------------------------------------------------- Gmail
def access_token():
    code = r'''#lang racket/base
(require oauth2 oauth2/client oauth2/storage/tokens json net/http-easy)
(define tok (get-token (getenv "USER") "gmail"))
(define (s x) (if (bytes? x) (bytes->string/utf-8 x) x))
(define creds (call-with-input-file "config/credentials.json" read-json))
(define r (post "https://oauth2.googleapis.com/token"
  #:form `((client_id . ,(hash-ref creds 'client_id))
           (client_secret . ,(hash-ref creds 'client_secret))
           (refresh_token . ,(s (token-refresh-token tok)))
           (grant_type . "refresh_token"))))
(display (hash-ref (response-json r) 'access_token))'''
    p = subprocess.run(['racket', '/dev/stdin'], input=code, capture_output=True,
                       text=True, cwd=REPO, timeout=120)
    if p.returncode or not p.stdout.startswith('ya29.'):
        sys.exit('token refresh failed: ' + p.stderr[-500:])
    return p.stdout.strip()

TOKEN = None
def gmail(path, **q):
    url = 'https://gmail.googleapis.com/gmail/v1/users/me/' + path
    if q:
        url += '?' + urllib.parse.urlencode(q, doseq=True)
    for i in range(7):
        try:
            req = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + TOKEN})
            return json.load(urllib.request.urlopen(req, timeout=60))
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503):
                time.sleep(2 ** i); continue
            raise
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            time.sleep(2 ** i)
    raise RuntimeError('gmail gave up: ' + path)

def list_ids(q, cap=10 ** 9):
    out, tok = [], None
    while len(out) < cap:
        kw = {'q': q, 'maxResults': 500, **({'pageToken': tok} if tok else {})}
        r = gmail('messages', **kw)
        out += r.get('messages', [])
        tok = r.get('nextPageToken')
        if not tok:
            break
    return out

def addr_of(from_):
    m = re.search(r'<([^>]+)>', from_ or '')
    return (m.group(1) if m else (from_ or '')).strip().lower()

def summarize(m):
    h = {x['name'].lower(): x['value'] for x in m['payload'].get('headers', [])}
    return {'id': m['id'], 'thread': m['threadId'], 'labels': m.get('labelIds', []),
            'ts': int(m['internalDate']) // 1000, 'snippet': m.get('snippet', ''),
            'h': {k: h.get(k.lower()) for k in HEADERS}}

def corresponded_before(msg):
    a = addr_of(msg['h']['From'])
    if not re.fullmatch(r'[^@ ]+@[^@ ]+', a):
        return None
    r = gmail('messages', q=f'in:sent to:{a} before:{msg["ts"]}', maxResults=1)
    return bool(r.get('messages'))

def wrote_earlier_in_thread(msg):
    t = gmail(f'threads/{msg["thread"]}', format='minimal')
    return any('SENT' in m.get('labelIds', []) and int(m['internalDate']) // 1000 < msg['ts']
               for m in t['messages'])

def add_thread_signal(data, f):
    every = [m for m in data['replied'] + data['random'] if 'in_thread' not in m]
    if every:
        with ThreadPoolExecutor(8) as ex:
            for m, v in zip(every, ex.map(wrote_earlier_in_thread, every)):
                m['in_thread'] = v
        f.write_text(json.dumps(data))
    return data

def build_dataset():
    f = CACHE / 'dataset.json'
    if f.exists():
        return add_thread_signal(json.loads(f.read_text()), f)
    now = int(time.time())
    # Replied-to: in threads Peter sent to, the inbound message just before
    # one of his sends. One per thread, so long threads don't dominate.
    sent = list_ids(f'in:sent after:{now - DAYS_REPLIED * 86400}')
    threads = sorted({m['threadId'] for m in sent})
    random.shuffle(threads)
    print(f'{len(sent)} sent messages in {len(threads)} threads', flush=True)

    def replied_in(tid):
        t = gmail(f'threads/{tid}', format='metadata', metadataHeaders=HEADERS)
        ms = sorted((summarize(m) for m in t['messages']), key=lambda m: m['ts'])
        mine = {addr_of(m['h']['From']) for m in ms if 'SENT' in m['labels']}
        pick = None
        for prev, cur in zip(ms, ms[1:]):
            if ('SENT' in cur['labels'] and 'SENT' not in prev['labels']
                    and 'DRAFT' not in prev['labels']
                    and addr_of(prev['h']['From']) not in mine
                    and prev['ts'] >= now - DAYS_REPLIED * 86400):
                subj = (cur['h']['Subject'] or '').lower()
                prev['kind'] = 'forward' if re.match(r'\s*(fwd?|fw):', subj) else 'reply'
                pick = prev
        return pick

    with ThreadPoolExecutor(8) as ex:
        replied = [m for m in ex.map(replied_in, threads[:int(N_REPLIED * 1.6)]) if m][:N_REPLIED]

    # Random recent inbound: what the daemon actually faces each day.
    pool = list_ids(f'after:{now - DAYS_RANDOM * 86400} -in:sent -in:chats -in:drafts')
    sample = random.sample(pool, min(N_RANDOM, len(pool)))
    with ThreadPoolExecutor(8) as ex:
        rand = list(ex.map(lambda m: summarize(gmail(f'messages/{m["id"]}', format='metadata',
                                                     metadataHeaders=HEADERS)), sample))
    for m in rand:
        m['kind'] = 'random'
    every = replied + rand
    with ThreadPoolExecutor(8) as ex:
        for m, c in zip(every, ex.map(corresponded_before, every)):
            m['corresponded'] = c
    data = {'replied': replied, 'random': rand, 'built': now}
    return add_thread_signal(data, f)

# ---------------------------------------------------------------- prompts
def racket_prompt(name):
    src = (REPO / 'config/classifier-prompts.rkt').read_text()
    m = re.search(rf'\(define {name}\n  #<<PROMPT\n(.*?)\nPROMPT\n', src, re.S)
    return m.group(1)

def human_only(p):
    """experiment-4 minus its one non-human rule: keep only what a person
    wrote. Measures what 'fuck everything else' costs."""
    p2 = re.sub(r'3\. It needs action from Peter.*?money moved\)\.\n', '', p, flags=re.S)
    p2 = p2.replace('4. A calendar invitation', '3. A calendar invitation')
    p2 = p2.replace(', unless rule 3 applies (e.g. payment failed, service\n  suspended).',
                    ',\n  including payment failures and account alerts.')
    p2 = p2.replace(',\n  unless it asks Peter specifically to sign, pay, or respond by a date.',
                    ', even when\n  they ask him to sign, pay or respond.')
    p2 = p2.replace('- Anything Peter sent himself',
                    '- System-generated alerts of every kind (balance, overdue bill, fraud,\n'
                    '  security, account status), however urgent they sound.\n'
                    '- Anything Peter sent himself')
    assert p2 != p and 'rule 3' not in p2 and 'It needs action' not in p2, 'human_only drifted'
    return p2

LABELS = (CACHE / 'labels.txt')
def fill(p):
    ctx_f = REPO / 'config/personal-context.txt'
    ctx = ('Context: ' + ctx_f.read_text().strip() + '\n') if ctx_f.exists() else ''
    labels = LABELS.read_text().rstrip('\n') if LABELS.exists() else 'None (first email being processed)'
    return p.replace('{existing_labels}', labels).replace('{personal_context}', ctx)

def email_text(m):
    """Mirror of format-email-for-llm in src/llm-classifier.rkt."""
    h = m['h']
    bulk = [k for k in ('List-Unsubscribe', 'List-Id') if h.get(k)]
    if h.get('Precedence'):
        bulk.append(f'Precedence: {h["Precedence"]}')
    if h.get('Auto-Submitted') and h['Auto-Submitted'].lower() != 'no':
        bulk.append(f'Auto-Submitted: {h["Auto-Submitted"]}')
    yn = {True: 'yes', False: 'no', None: 'unknown'}
    return (f"From: {h['From'] or 'Unknown'}\nTo: {h['To'] or 'Unknown'}\n"
            + (f"Cc: {h['Cc']}\n" if h.get('Cc') else '')
            + f"Date: {h['Date'] or 'Unknown'}\nSubject: {h['Subject'] or '(no subject)'}\n\n"
            f"Bulk/automation headers: {', '.join(bulk) if bulk else 'none'}\n"
            f"Peter has emailed this sender before: {yn[m['corresponded']]}\n"
            f"Peter already wrote in this thread: {yn[m.get('in_thread')]}\n\n"
            f"Content:\n{m['snippet'] or '(no content)'}")

SCHEMA = {'type': 'object', 'additionalProperties': False,
          'required': ['label', 'should_archive', 'rationale'],
          'properties': {'label': {'type': 'string'}, 'should_archive': {'type': 'boolean'},
                         'rationale': {'type': 'string'}}}

def classify(prompt, m):
    body = json.dumps({'model': MODEL, 'max_tokens': 1024,
                       'output_config': {'format': {'type': 'json_schema', 'schema': SCHEMA}},
                       'messages': [{'role': 'user', 'content':
                                     f'{prompt}\n\nEmail to classify:\n\n{email_text(m)}'}]}).encode()
    for i in range(8):
        try:
            req = urllib.request.Request('https://api.anthropic.com/v1/messages', data=body, headers={
                'x-api-key': os.environ['ANTHROPIC_API_KEY'], 'anthropic-version': '2023-06-01',
                'content-type': 'application/json'})
            r = json.load(urllib.request.urlopen(req, timeout=120))
            return json.loads(r['content'][0]['text'])
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 529):
                time.sleep(min(60, 2 ** i)); continue
            raise RuntimeError(e.read().decode()[:300])
        except (urllib.error.URLError, TimeoutError, ConnectionError, json.JSONDecodeError):
            time.sleep(min(60, 2 ** i))
    return None

FORMAT_VERSION = 2  # bump when email_text changes; keys the result cache

def run_prompt(name, prompt, msgs):
    import hashlib
    key = hashlib.sha256(f'{FORMAT_VERSION}\n{MODEL}\n{prompt}'.encode()).hexdigest()[:10]
    f = CACHE / f'results-{name}-{key}.json'
    done = json.loads(f.read_text()) if f.exists() else {}
    todo = [m for m in msgs if m['id'] not in done]
    if todo:
        print(f'{name}: classifying {len(todo)}', flush=True)
        with ThreadPoolExecutor(10) as ex:
            for i, (m, r) in enumerate(zip(todo, ex.map(lambda m: classify(prompt, m), todo))):
                if r is not None:
                    done[m['id']] = r
                if i % 50 == 49:
                    f.write_text(json.dumps(done))
        f.write_text(json.dumps(done))
    return {k: (not v['should_archive']) for k, v in done.items()}, done

# ---------------------------------------------------------------- baselines
def bulk(m):
    h = m['h']
    return bool(h.get('List-Unsubscribe') or h.get('List-Id')
                or (h.get('Precedence') or '').lower() in ('bulk', 'list', 'junk')
                or (h.get('Auto-Submitted') or 'no').lower() != 'no')

BASELINES = {
    'gmail Primary tab': lambda m: not any(l in m['labels'] for l in (
        'CATEGORY_PROMOTIONS', 'CATEGORY_SOCIAL', 'CATEGORY_UPDATES', 'CATEGORY_FORUMS')),
    'no bulk headers': lambda m: not bulk(m),
    'emailed sender before': lambda m: m['corresponded'] is True,
    'emailed before OR no bulk': lambda m: m['corresponded'] is True or not bulk(m),
    'emailed before AND no bulk': lambda m: m['corresponded'] is True and not bulk(m),
    'wrote earlier in thread': lambda m: m.get('in_thread') is True,
}

# ---------------------------------------------------------------- main
def main():
    global TOKEN
    TOKEN = access_token()
    data = build_dataset()
    rep, rnd = data['replied'], data['random']
    print(f"dataset: {len(rep)} replied-to ({sum(m['kind'] == 'forward' for m in rep)} forwards), "
          f"{len(rnd)} random recent inbound\n", flush=True)
    exp4 = fill(racket_prompt('experiment-4-prompt'))
    prompts = {'experiment-4': exp4, 'experiment-5': fill(racket_prompt('experiment-5-prompt'))}
    if os.environ.get('EVAL_ABLATION'):  # exp-4 without its non-human rule
        prompts['exp-4 minus rule 3'] = fill(human_only(racket_prompt('experiment-4-prompt')))
    methods, raw = dict(BASELINES), {}
    for name, p in prompts.items():
        keep, raw[name] = run_prompt(name, p, rep + rnd)
        methods['LLM ' + name] = (lambda keep: lambda m: keep.get(m['id']))(keep)
    primary, llm5 = BASELINES['gmail Primary tab'], methods['LLM experiment-5']
    methods['Primary AND exp-5'] = lambda m: primary(m) and llm5(m)
    methods['Primary OR exp-5'] = lambda m: primary(m) or llm5(m)

    replies = [m for m in rep if m['kind'] == 'reply']
    print(f"{'method':32} {'recall':>7} {'(replies)':>9} {'keep rate':>9} {'~kept/day':>9}")
    for name, f in methods.items():
        def rate(ms):
            v = [f(m) for m in ms]
            v = [x for x in v if x is not None]
            return sum(v) / len(v) if v else float('nan')
        kr = rate(rnd)
        print(f'{name:32} {rate(rep):7.1%} {rate(replies):9.1%} {kr:9.1%} {kr * 70:9.0f}')

    out = CACHE / 'misses.txt'
    with out.open('w') as fh:
        for name in prompts:
            fh.write(f'\n==== {name}: replied-to but ARCHIVED ====\n')
            for m in rep:
                r = raw[name].get(m['id'])
                if r and r['should_archive']:
                    fh.write(f"[{m['kind']}] {m['h']['From'][:50]} | {(m['h']['Subject'] or '')[:70]}\n"
                             f"    {r['rationale'][:200]}\n")
            fh.write(f'\n==== {name}: random inbound KEPT ====\n')
            for m in rnd:
                r = raw[name].get(m['id'])
                if r and not r['should_archive']:
                    fh.write(f"{m['h']['From'][:50]} | {(m['h']['Subject'] or '')[:70]}\n"
                             f"    {r['rationale'][:200]}\n")
    print(f'\nper-message misses and keeps: {out}')

if __name__ == '__main__':
    main()
