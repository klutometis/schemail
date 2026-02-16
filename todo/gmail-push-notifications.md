# Gmail Push Notifications via Cloud Pub/Sub

## Overview

Gmail supports real-time push notifications via Google Cloud Pub/Sub instead of polling. This allows the system to receive instant notifications when emails arrive, rather than checking every N minutes.

**Official docs:** https://developers.google.com/workspace/gmail/api/guides/push

---

## Architecture: How It Works

```
New email arrives in Gmail
  ↓
Gmail publishes message to Cloud Pub/Sub topic
  ↓
Cloud Pub/Sub delivers to subscription
  ↓ (two options)
  
OPTION A: Push (Webhook)          OPTION B: Pull (Polling)
→ HTTP POST to your endpoint      → Your app polls subscription
→ Your endpoint processes          → App processes message
→ Returns 200 OK                   → App acknowledges message
```

**Key insight:** You still need an endpoint, but Gmail notifies YOU instead of you polling Gmail.

---

## What You Need

### 1. Google Cloud Project Setup

**Prerequisites:**
- Google Cloud project (same one with Gmail API enabled)
- Billing enabled (Pub/Sub has free tier: 10GB/month)
- Cloud Pub/Sub API enabled

**Steps:**
1. Enable Cloud Pub/Sub API in Google Cloud Console
2. Create IAM service account permissions
3. Set up topic and subscription

### 2. Cloud Pub/Sub Topic

**Create a topic:**
```bash
# Using gcloud CLI
gcloud pubsub topics create gmail-notifications --project=YOUR_PROJECT_ID
```

**Topic name format:**
```
projects/YOUR_PROJECT_ID/topics/gmail-notifications
```

### 3. Grant Gmail Publishing Rights

**Critical step:** Gmail needs permission to publish to your topic.

```bash
# Grant Gmail service account publish permission
gcloud pubsub topics add-iam-policy-binding gmail-notifications \
  --member=serviceAccount:gmail-api-push@system.gserviceaccount.com \
  --role=roles/pubsub.publisher
```

**Without this:** Watch requests will fail with permission errors.

### 4. Create Subscription

**Two options:**

**Option A: Push Subscription (Webhook)**
```bash
gcloud pubsub subscriptions create gmail-push-sub \
  --topic=gmail-notifications \
  --push-endpoint=https://your-domain.com/gmail-webhook
```

**Option B: Pull Subscription (Polling)**
```bash
gcloud pubsub subscriptions create gmail-pull-sub \
  --topic=gmail-notifications
```

---

## Implementation Options

### Option 1: Pull Subscription (Simpler for Local Dev)

**How it works:**
- Your app polls the Pub/Sub subscription for messages
- No public endpoint needed
- Works on localhost
- Still faster than polling Gmail directly

**Pros:**
- ✅ Works locally without ngrok
- ✅ No public endpoint to secure
- ✅ Simpler deployment
- ✅ Good for single-user/personal use

**Cons:**
- ⚠️ Still polling (Pub/Sub instead of Gmail)
- ⚠️ Slightly higher latency (~5-10 seconds vs instant)
- ⚠️ Uses more Cloud resources

**Implementation:**
```racket
;; Poll Pub/Sub subscription every 5 seconds
(define (pubsub-daemon)
  (let loop ()
    (define messages (pull-pubsub-messages))
    (for-each process-gmail-notification messages)
    (sleep 5)
    (loop)))
```

**Libraries needed:**
- Google Cloud Pub/Sub client library
- Or: REST API calls to `https://pubsub.googleapis.com/v1/`

---

### Option 2: Push Subscription (Ngrok for Local Testing)

**How it works:**
- Pub/Sub sends HTTP POST to your endpoint
- Instant notifications (< 1 second)
- Your endpoint must be publicly accessible

**For local testing: Use ngrok**

**Setup ngrok:**
```bash
# Install ngrok
brew install ngrok  # or download from ngrok.com

# Start ngrok tunnel to local port 8080
ngrok http 8080
```

**Output:**
```
Forwarding  https://abc123.ngrok.io -> http://localhost:8080
```

**Create push subscription with ngrok URL:**
```bash
gcloud pubsub subscriptions create gmail-push-sub \
  --topic=gmail-notifications \
  --push-endpoint=https://abc123.ngrok.io/gmail-webhook
```

**Pros:**
- ✅ Instant notifications
- ✅ More efficient (no polling)
- ✅ Good for testing push flow locally

**Cons:**
- ❌ ngrok URL changes on restart (unless paid plan)
- ❌ Need to update subscription each time
- ❌ ngrok free tier has limits
- ❌ Not suitable for production

**Implementation:**
```racket
;; HTTP server to receive push notifications
(define (start-webhook-server port)
  (serve/servlet
   (lambda (req)
     (match (request-uri req)
       [(regexp #rx"/gmail-webhook")
        (define body (request-post-data/raw req))
        (process-pubsub-push body)
        (response/plain "OK")]
       [_ (response/plain "Not Found" #:code 404)]))
   #:port port))
```

---

### Option 3: Cloud Run (Production Push Endpoint)

**How it works:**
- Deploy your webhook handler to Google Cloud Run
- Stable HTTPS endpoint
- Auto-scales to zero when idle
- Only pay for actual requests

**Deployment:**
```dockerfile
# Dockerfile
FROM racket/racket:latest
WORKDIR /app
COPY . .
RUN raco pkg install --auto simple-oauth2 http-easy
CMD ["racket", "webhook-server.rkt"]
```

```bash
# Deploy to Cloud Run
gcloud run deploy gmail-webhook \
  --source . \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated
```

**Create subscription with Cloud Run URL:**
```bash
gcloud pubsub subscriptions create gmail-push-sub \
  --topic=gmail-notifications \
  --push-endpoint=https://gmail-webhook-xyz.run.app/webhook
```

**Pros:**
- ✅ Stable production endpoint
- ✅ Auto-scaling
- ✅ Pay-per-use (free tier: 2M requests/month)
- ✅ HTTPS by default
- ✅ Managed infrastructure

**Cons:**
- ⚠️ Requires deployment step
- ⚠️ Slightly more complex
- ⚠️ Need to handle Cloud Run cold starts

---

### Option 4: Cloud Functions (Serverless Alternative)

**Similar to Cloud Run but function-based:**
```python
# main.py
def gmail_webhook(request):
    """Handle Gmail push notification"""
    pubsub_message = request.get_json()
    # Process notification
    return ('', 204)
```

```bash
gcloud functions deploy gmail-webhook \
  --runtime python311 \
  --trigger-http \
  --allow-unauthenticated
```

---

## Gmail API Watch Request

**Once Pub/Sub is set up, configure Gmail to send notifications:**

```racket
;; Watch user's mailbox for changes
(define (gmail-watch topic-name)
  (define request-body
    (hasheq 'topicName topic-name
            'labelIds '("INBOX")
            'labelFilterBehavior "INCLUDE"))
  
  (gmail-api-request "watch"
                     #:method "POST"
                     #:data (jsexpr->string request-body)))
```

**HTTP equivalent:**
```bash
POST https://www.googleapis.com/gmail/v1/users/me/watch
Content-Type: application/json

{
  "topicName": "projects/YOUR_PROJECT/topics/gmail-notifications",
  "labelIds": ["INBOX"],
  "labelFilterBehavior": "INCLUDE"
}
```

**Response:**
```json
{
  "historyId": "1234567890",
  "expiration": "1431990098200"
}
```

**Important notes:**
- Watch expires after ~7 days (renew automatically)
- historyId is the starting point for changes
- You'll immediately get a test notification

---

## Processing Notifications

**Pub/Sub message format (push):**
```json
{
  "message": {
    "data": "eyJlbWFpbEFkZHJlc3MiOiJ1c2VyQGV4YW1wbGUuY29tIiwiaGlzdG9yeUlkIjoxMjM0fQ==",
    "messageId": "1234567890",
    "publishTime": "2025-02-15T12:34:56.789Z"
  },
  "subscription": "projects/PROJECT/subscriptions/SUB"
}
```

**Decoded data (base64):**
```json
{
  "emailAddress": "user@example.com",
  "historyId": 1234
}
```

**Processing steps:**
1. Decode base64 message.data
2. Extract historyId
3. Fetch changes since last historyId using `users.history.list`
4. Process new emails
5. Store new historyId

**Important:** Notification doesn't contain the actual email - just tells you something changed. You still need to fetch using Gmail API.

---

## Recommended Approach for Schemail

### For Personal/Single-User Use: Pull Subscription

**Pros:**
- No public endpoint needed
- Works on personal laptop
- Simple deployment
- No ngrok needed

**Implementation plan:**
1. Create Pub/Sub topic
2. Create pull subscription
3. Add Racket Pub/Sub polling loop
4. Poll every 5-10 seconds
5. Process notifications

**Cost:** Free tier easily covers personal use

---

### For Multi-User/Production: Cloud Run + Push

**Pros:**
- Instant notifications
- Scalable to many users
- Stable endpoint
- Professional setup

**Implementation plan:**
1. Create Pub/Sub topic
2. Deploy webhook to Cloud Run
3. Create push subscription
4. Webhook processes notifications
5. Triggers classification pipeline

**Cost:** ~$0-5/month for moderate use

---

## Comparison vs Polling

| Feature | Polling (current) | Pub/Sub Pull | Pub/Sub Push (ngrok) | Pub/Sub Push (Cloud Run) |
|---------|------------------|--------------|---------------------|-------------------------|
| **Latency** | 5-60 min | 5-10 sec | < 1 sec | < 1 sec |
| **Setup complexity** | Simple | Medium | Medium | High |
| **Local dev** | ✅ Easy | ✅ Easy | ⚠️ ngrok needed | ❌ Deploy needed |
| **Production** | ✅ Works | ✅ Works | ❌ Not suitable | ✅ Best |
| **Cost** | Gmail API only | + Pub/Sub | + Pub/Sub + ngrok | + Pub/Sub + Cloud Run |
| **Public endpoint** | ❌ No | ❌ No | ✅ Yes (ngrok) | ✅ Yes (stable) |
| **Maintenance** | Low | Low | Medium (ngrok restarts) | Low (auto-managed) |

---

## Implementation Steps (Pull Subscription - Recommended for MVP)

### 1. Google Cloud Setup

```bash
# Enable Pub/Sub API
gcloud services enable pubsub.googleapis.com

# Create topic
gcloud pubsub topics create gmail-notifications

# Grant Gmail publishing rights
gcloud pubsub topics add-iam-policy-binding gmail-notifications \
  --member=serviceAccount:gmail-api-push@system.gserviceaccount.com \
  --role=roles/pubsub.publisher

# Create pull subscription
gcloud pubsub subscriptions create gmail-pull-sub \
  --topic=gmail-notifications
```

### 2. Racket Implementation

**Add Pub/Sub client:**
```racket
;; src/pubsub.rkt
(define (pull-pubsub-messages subscription-name)
  ;; Use Google Cloud Pub/Sub REST API
  ;; GET https://pubsub.googleapis.com/v1/{subscription}:pull
  ...)

(define (acknowledge-message subscription-name ack-id)
  ;; POST https://pubsub.googleapis.com/v1/{subscription}:acknowledge
  ...)
```

**Add daemon mode:**
```racket
;; bin/schemail daemon
(define (pubsub-daemon interval)
  (gmail-watch "projects/PROJECT/topics/gmail-notifications")
  (let loop ()
    (define messages (pull-pubsub-messages "gmail-pull-sub"))
    (for-each process-notification messages)
    (sleep interval)
    (loop)))
```

### 3. Register Watch

```racket
;; Call once to start receiving notifications
(gmail-watch "projects/PROJECT/topics/gmail-notifications")
```

### 4. Process Notifications

```racket
(define (process-notification pubsub-msg)
  (define decoded (base64-decode (hash-ref pubsub-msg 'data)))
  (define gmail-data (string->jsexpr decoded))
  (define history-id (hash-ref gmail-data 'historyId))
  
  ;; Fetch changes since last history-id
  (define changes (gmail-history-list history-id))
  
  ;; Process new emails
  (for-each classify-email (extract-new-messages changes)))
```

---

## Next Steps

1. **Decide on approach:**
   - Pull subscription (simpler, localhost-friendly)
   - Push with Cloud Run (production-ready, instant)

2. **Implement Pub/Sub client:**
   - Add `src/pubsub.rkt` with REST API calls
   - Test pull/push message delivery

3. **Add daemon mode:**
   - `bin/schemail daemon --pubsub`
   - Poll subscription or run webhook server

4. **Test locally:**
   - Send test email
   - Verify notification received
   - Verify classification runs

5. **Deploy (if using push):**
   - Containerize webhook server
   - Deploy to Cloud Run
   - Update subscription endpoint

---

## Estimated Costs (Personal Use)

**Cloud Pub/Sub:**
- Free tier: 10GB/month
- Typical notification: ~200 bytes
- 10GB = ~50M notifications/month
- **Cost:** $0/month (within free tier)

**Cloud Run (if using push):**
- Free tier: 2M requests/month
- 100 emails/day = 3K notifications/month
- **Cost:** $0/month (within free tier)

**Total incremental cost:** $0/month for personal use

---

## Security Considerations

### For Push Subscriptions

**Verify Pub/Sub messages:**
```racket
;; Validate JWT token from Pub/Sub
(define (verify-pubsub-request headers body)
  (define auth-header (hash-ref headers 'authorization))
  (verify-google-jwt auth-header))
```

**Or: Use push endpoint authentication:**
```bash
gcloud pubsub subscriptions create gmail-push-sub \
  --topic=gmail-notifications \
  --push-endpoint=https://your-domain.com/webhook \
  --push-auth-service-account=SERVICE_ACCOUNT_EMAIL
```

### For Pull Subscriptions

**Use OAuth2 with Pub/Sub scope:**
```racket
(define pubsub-scopes
  (list "https://www.googleapis.com/auth/pubsub"))
```

---

## Resources

- [Gmail Push Notifications Guide](https://developers.google.com/workspace/gmail/api/guides/push)
- [Cloud Pub/Sub Quickstart](https://cloud.google.com/pubsub/docs/quickstart-client-libraries)
- [Cloud Run Quickstart](https://cloud.google.com/run/docs/quickstarts)
- [Pub/Sub Push Authentication](https://cloud.google.com/pubsub/docs/push#authentication_and_authorization)

---

## Conclusion

**Recommended path:**
1. **MVP:** Polling daemon (current approach, simplest)
2. **V2:** Pull subscription daemon (5-10 sec latency, no public endpoint)
3. **Production:** Cloud Run + push subscription (instant, scalable)

The beauty of Pub/Sub is you can start with pull (simple) and upgrade to push (instant) without changing Gmail watch setup - just switch subscription type.
