# Scale and identity: what happens when…

## 1. …thousands (or millions) of enquiries arrive at the same moment?

| Layer | What it does under load | Where |
|---|---|---|
| Website / app | Static files on Firebase Hosting's global CDN. Each visitor's chat talks to Firestore directly; no app server in between. | `firebase.json` |
| Database | Cloud Firestore scales automatically. Every lead is its own document, so visitors never write to the same document. | data model |
| AI workers | Cloud Functions (2nd gen = Cloud Run): adds instances as traffic grows (`MAX_INSTANCES`, default 100), and each instance handles 40 conversations at once because the work is mostly waiting for the AI. | `functions/src/index.ts` |
| **The real ceiling: AI quota** | Free AI keys allow only a limited number of requests per minute. That limit runs out long before the servers do, so we spend fewer AI calls in the four ways below. | |
| ① Answer cache | The same first question from different strangers is answered by the AI **once**; everyone else gets that answer instantly. Edit the knowledge base and every cached answer becomes invalid. | `cache.ts`, `brain.ts` |
| ② Single-flight | If 1,000 identical questions land in the same second, **one** worker asks the AI and the other 999 reuse its answer the moment it lands (tested: 1,000 requests → 1 AI call). | `cache.ts` + test |
| ③ One reply per person | Someone who sends 3 messages in 5 seconds gets **one** thoughtful reply covering all three, not three replies racing each other. Duplicate event deliveries are ignored. | `brain.ts → respond()` |
| ④ Never lost | If every AI key is busy, the student gets an instant "our counsellor will reply in a few minutes". The conversation then retries automatically (2, 4, 8… minutes), and after 3 failures it is flagged for a human. | `brain.ts`, `aiRetry` in `index.ts` |
| Key pool | Several Gemini keys, then Groq, then OpenRouter. A rate-limited key is skipped in milliseconds. | `ai.ts` |
| No hot documents | A Firestore document handles about 1 write per second, so shared counters are spread over 10 shards, provider health is reported at most once a minute, and leads are assigned by a hash (no shared counter). | `stats.ts`, `ai.ts`, `assign.ts` |

**See it:** Admin → Demo → **Load test (30 at once)**, then Desk → Reports → **Scale & cost**.
30 visitors asking 3 common questions cost about **3 AI calls** instead of 30.

**Honest limits:**
- For real millions you would move to a paid Gemini tier (Vertex AI with provisioned throughput).
- You would put AI work on a rate-limited Cloud Tasks queue, so spikes are smoothed instead of retried.
- You would turn on Firebase App Check against bots.

None of these changes the design.

## 2. …the same question comes from different people?
Each person gets **their own lead**, because identity is decided by phone, email and the student's name, never by the question. The **answer** to an identical first question is shared through the cache. Everyone gets the same, correct, Guard-checked answer, which also fixes the pain in the problem statement: "two different answers on two channels".

Only a stranger's **first text** message is cached. Once a conversation is personal (background, aptitude, objections, voice notes), every reply is generated for that person. The cache key includes:
- the question, normalised for case, punctuation and Devanagari digits
- the channel
- everything already known about the lead
- the knowledge-base version
- the open demo slots

So a cached answer is exactly what the AI would have said to that person.

## 3. …one admission, many enquirers (the student, a parent, a friend, other accounts)?
**One lead per student.** Everyone asking about that student is a **contact** on it (relation: self / parent / friend…), and the whole conversation is one timeline.

| Situation | Result |
|---|---|
| Rahul fills the form (098765 43210), then writes on WhatsApp as राहुल पाटल (+91 98765-43210) | **Merged**: same phone (any format), same person (any script) |
| His father calls from his own number and gives Rahul's number | **Merged**: the student's phone matches; the father is added as a parent contact |
| A friend on Telegram asks about Rahul and gives Rahul's number | **Merged**: friend added as a contact |
| The father gives only the name "Rahul Patil", no number | **Not merged.** A "Possible duplicate" card appears for a counsellor to confirm, and Asha politely asks for Rahul's number. A name alone never merges: Maharashtra has thousands of Rahul Patils. |
| Rahul chats on his laptop and then on his phone (two anonymous accounts) | Merged as soon as he shares his number or email on either; both devices then see one chat |

## 4. …different accounts asking the same thing for *different* people?

| Situation | Result |
|---|---|
| The same father asks about his daughter Priya | **A second lead** (a second admission), **linked** to Rahul's as "same family". Never merged. |
| Siblings share one family phone | Two leads, linked |
| An agent or teacher enquires for several students | One lead per student, all linked by the agent's phone |
| Two strangers ask the identical question | Two leads; the answer is served from the cache |

Merging compares **given names**, not just whole strings. Here is the difference for siblings:
- Whole-string similarity scores "Priya Patil" vs "Rahul Patil" at 0.87, high enough to merge them wrongly.
- Given-name similarity scores them at 0.60, so they are treated as two people (`personSimilarity` in `identity.ts`, unit-tested).

A counsellor can always fix an edge case with one tap:
- **Merge** on a linked card
- **Different people** on a duplicate card

**See it:** Desk → 🧪 **Simulate**, then run presets **1 → 5** in order.
