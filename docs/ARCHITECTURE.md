# AI Lead Desk — Architecture & Data Model

Use this page in the mentor round. GitHub draws the diagrams automatically.

## 60-second explanation

1. **Every channel lands in one place.** WhatsApp, the web chat (QR code), the website form, Instagram bio link and walk-ins all create a *lead* in Cloud Firestore.
2. **One AI brain answers everyone.** A Cloud Function runs "Asha", our AI counsellor on Google Gemini. Same brain on every channel, so the same person always gets the same answer.
3. **The server decides what matters**: aptitude scoring, lead score, follow-up timing/channel and calendar booking are computed in code, not by the model. **A Guard checks every reply** against the institute's knowledge base, so the AI can never invent a fee, discount or job guarantee.
4. **Identity merge** recognises that *Rahul Patil* (form, 098765 43210) and *राहुल पाटील* (WhatsApp, +91 98765 43210) are one person.
5. **No lead is forgotten.** A heartbeat every 5 minutes sends demo reminders and next-best-action follow-ups, outside quiet hours.
6. **Counsellors work from a live desk** (Flutter, Android + web): score, 3-line summary, objections, suggested message, one-tap take-over.
7. **Staff access is controlled.** Staff sign in with Google or email (one merged account), and an admin approves each counsellor.

---

## 1. System architecture

```mermaid
flowchart LR
  subgraph CH["Where enquiries come from"]
    WA["WhatsApp<br/>text + voice notes"]
    QR["Web chat via QR<br/>no login"]
    FORM["Website form"]
    IG["Instagram bio link"]
    WALK["Walk-in entry<br/>GPS + IST time"]
  end

  subgraph APP["Flutter app: Android + Web"]
    CHAT["Student chat"]
    DESK["Counsellor desk"]
    ADMIN["Admin: team approvals,<br/>courses, QR, time machine"]
  end

  subgraph FB["Firebase"]
    AUTH["Firebase Auth<br/>Google + Email (linked)<br/>Anonymous for students"]
    FS[("Cloud Firestore<br/>leads, messages, users,<br/>kb, slots, events")]
    subgraph CF["Cloud Functions, Mumbai region"]
      BRAIN["Asha: AI counsellor"]
      GUARD["Guard"]
      MERGE["Identity merge"]
      HB["Heartbeat every 5 min<br/>next-best-action engine"]
      API["api: admin, simulators,<br/>merge, assign, book"]
      HOOK["metaWebhook · telegramWebhook<br/>intakeWebhook · callWebhook"]
      STAFF["Staff approval"]
    end
  end

  GEM["Gemini → Groq → OpenRouter<br/>(free key pool)"]
  CAL["Google Calendar"]
  META["Meta WhatsApp Cloud API"]

  QR --> CHAT
  FORM --> CHAT
  IG --> CHAT
  WALK --> DESK
  WA --> META --> HOOK --> FS
  CHAT --> FS
  DESK <--> FS
  ADMIN <--> FS
  APP --> AUTH
  FS -- "new message" --> BRAIN
  BRAIN <--> GEM
  BRAIN --> GUARD --> FS
  BRAIN --> MERGE --> FS
  HB --> FS
  HB --> META
  BRAIN --> CAL
  APP --> API
  BRAIN --> META
  FS -- "new staff" --> STAFF
```

## 2. What happens when a student sends a voice note

```mermaid
sequenceDiagram
  autonumber
  actor S as Student
  participant C as Flutter chat
  participant DB as Firestore
  participant F as Cloud Function
  participant G as Gemini
  participant D as Counsellor desk

  S->>C: Marathi voice note at 11 PM
  C->>DB: add message (role user, audio)
  DB-->>F: onMessageCreated trigger
  F->>DB: read lead, last 24 messages, knowledge base, open demo slots
  F->>G: rules + knowledge base + history + audio
  G-->>F: JSON: reply, language, score, summary, objections, next action, slot
  F->>F: Guard checks every amount, percent and promise
  alt draft invented something
    F->>G: rewrite using knowledge base only
    G-->>F: safe reply
  end
  F->>DB: AI reply + lead card update + slot booking (transaction)
  DB-->>C: reply appears in seconds
  DB-->>D: lead card updates live (score, summary, objections)
```

## 3. Firestore data model

```mermaid
erDiagram
  LEADS ||--o{ MESSAGES : "timeline"
  LEADS }o--o| SLOTS : "books demo"
  LEADS ||--o{ EVENTS : "activity log"
  USERS ||--o{ LEADS : "counsels"
  KB ||--o{ SLOTS : "courses"

  LEADS {
    string name
    string nameLatin "Devanagari to English letters"
    string phone "normalised to 10 digits"
    string waId "WhatsApp id"
    array sources "web, whatsapp, form, walkin, instagram"
    string firstSource "for conversion by source"
    string status "new, engaged, demo_booked, admitted, lost"
    int score "0 to 100"
    string temperature "hot, warm, cold"
    array summary "3 lines for the counsellor"
    array objections "fees, job_fear, family_approval"
    string suggestedMessage
    map nextAction "at, channel, message, reason, done"
    map aptitude "status, asked, correct, level"
    map recommendation "courseId, reason"
    map booking "slotId, startAt, calendarUrl, reminders"
    bool aiPaused "counsellor took over"
    string assignedTo
    string mergedInto "set on the duplicate"
    array viewerUids "who may read it in the student chat"
  }
  MESSAGES {
    string role "user, ai, counsellor, system"
    string channel
    string text
    string audioB64 "short voice note"
    string transcript
    map meta "guard result, kind, by"
    timestamp createdAt
  }
  USERS {
    string name
    string email
    array providers "google.com, password"
    string role "pending, counsellor, admin, rejected"
  }
  KB {
    array courses "fee, EMI, duration, next batch"
    array scholarships
    map policies "placement, refund, demo"
  }
  SLOTS {
    string title
    timestamp startAt
    int capacity
    int booked
  }
  EVENTS {
    string type "merge, guard_block, booking, reminder, followup"
    string leadId
    map data
  }
```

## 4. Lead journey

```mermaid
stateDiagram-v2
  [*] --> new: enquiry on any channel
  new --> engaged: Asha starts counselling
  engaged --> engaged: aptitude check, objections, follow-ups
  engaged --> demo_booked: student picks a real slot
  demo_booked --> demo_booked: reminders 24 h and 1 h before
  demo_booked --> admitted: counsellor marks admitted
  engaged --> lost
  demo_booked --> lost
  admitted --> [*]
```

## 5. Staff sign-in and approval

```mermaid
flowchart TD
  A["Staff opens Counsellor Desk"] --> B{"Signed in?"}
  B -- "No" --> C["Continue with Google<br/>or email + password"]
  C --> D["Same Gmail on both?<br/>Linked into ONE account"]
  D --> E["users record created<br/>role = pending"]
  B -- "Yes" --> E
  E --> F{"First staff account<br/>or in ADMIN_EMAILS?"}
  F -- "Yes" --> G["role = admin"]
  F -- "No" --> H["Waiting screen"]
  H --> I["Admin page shows request"]
  I -- "Approve" --> J["role = counsellor<br/>desk opens by itself"]
  I -- "Reject" --> K["Access not approved"]
  G --> L["Desk + Admin page"]
  J --> M["Desk"]
```

## 6. Security in one line each

- **Students** use an anonymous session and can read only the conversation they started (`viewerUids`).
- **Counsellors** (approved) read and work all leads; **admins** also edit courses, slots and the team.
- **AI replies, merges, reminders and events** are written only by Cloud Functions (admin SDK).
- **Secrets** (Gemini key, WhatsApp token) live in `functions/.env`, which is never committed.
