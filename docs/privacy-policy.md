# Hersciety — Privacy Policy

---

## ⚠️ ATTORNEY REVIEW REQUIRED BEFORE PUBLICATION

**This is a comprehensive draft, not legal advice, and not a substitute for qualified legal counsel.**

Hersciety operates an open-membership social platform for adults. The platform handles text-based user-generated content, operates a direct-messaging system that uses end-to-end encryption, collects and verifies real legal names while protecting their public display, and uses technical signals including device fingerprints and IP addresses for safety and fraud prevention. No image upload currently exists anywhere on the platform. Before this Privacy Policy is published, the owner must have it reviewed by a lawyer who is:

- Licensed to practice in Tennessee and familiar with applicable state, federal, and (when EU/UK launch occurs) international law
- Knowledgeable about data protection law including the California Consumer Privacy Act and its amendments (CCPA/CPRA), applicable state privacy statutes, and the FTC Act Section 5 unfair and deceptive acts standard
- Familiar with CSAM mandatory reporting obligations under 18 U.S.C. § 2258A as amended by the REPORT Act
- Aware of the NIST Privacy Framework (Version 1.0, January 2020) and its role in Tennessee's TIPA affirmative defense
- Experienced with social platform data practices and trust-and-safety compliance

**Specific areas of elevated legal risk on this platform that require attorney attention:**
1. The collection and verification of real legal names alongside pseudonymous public display -- confirm that the collection, storage, and limited-disclosure design is appropriately documented and that the opt-in display mechanism is clearly communicated and technically implemented before launch
2. CSAM reporting and evidence preservation obligations under 18 U.S.C. § 2258A -- confirm CyberTipline registration is complete and that the one-year preservation requirement is correctly implemented before any image upload feature is live
3. Device fingerprinting and IP retention -- confirm that the purposes and retention periods described here are accurate and sufficient under applicable law, including CCPA
4. All bracketed attorney notes in this document -- the retention brackets in Section 8 have been resolved by the owner; remaining brackets are attorney review notes that must not be published as-is
5. California CCPA/CPRA compliance -- confirm the rights described in Section 12 are complete and accurate, and confirm whether the platform meets the statutory thresholds that trigger the full CPRA regime
6. Data Processing Agreements with service providers -- see Section 7 for the list of vendors; DPAs should be in place before personal data flows to any of them
7. Retention periods -- periods in Section 8 have been set by the owner; confirm each is appropriate and technically implemented before publication

Do not publish this Privacy Policy without counsel review.

---

*Effective date: October 1, 2026*
*Last updated: October 7, 2026*

This Privacy Policy describes how Curry Co LLC ("Company," "we," "us," or "our") collects, uses, stores, and shares personal information when you use Hersciety, the social platform available at hersciety.com (the "Platform"). It also describes your rights and how to exercise them.

By creating an account or using the Platform, you agree to this Privacy Policy. If you do not agree, do not use the Platform.

This policy is incorporated into and made part of our Terms of Service.

---

## Table of Contents

1. About This Policy
2. What We Collect and Why
3. How We Use Your Information
4. Your Legal Name: Collected, Not Displayed
5. Direct Messages: An Important Disclosure
6. CSAM Detection and Mandatory Reporting
7. How We Share Your Information
8. Data Retention
9. Security
10. Your Rights and Choices
11. Cookies and Similar Technologies
12. California Residents
13. Minors
14. Changes to This Policy
15. Contact

---

## 1. About This Policy

**1.1 Who we are.** Hersciety is operated by Curry Co LLC, a Tennessee limited liability company. Our mailing address is 466 E Broadway Blvd, Jefferson City, TN 37760. Privacy questions and requests can be sent to legal@unitedfeminist.com.

**1.2 What this platform does.** Hersciety is a text-first social platform designed as a safe space for women and their allies. Members post publicly, reply in threads, follow each other, and send direct messages. Direct messages are end-to-end encrypted. Membership is fully open -- anyone who agrees to our Terms of Service and is 18 or older can create an account. Because both the platform's safety mission and our legal obligations require it, we collect and verify the real identity of every member while giving members control over what the public sees.

**1.3 Geographic scope.** The Platform currently serves members in the United States only. This policy is written for that context. If we expand to the European Union, the United Kingdom, or other jurisdictions, this policy will be updated and reviewed before that expansion occurs. Nothing in this policy creates rights under the GDPR or UK GDPR.

**1.4 NIST Privacy Framework.** This policy is structured to reasonably conform to the NIST Privacy Framework, Version 1.0 (January 2020), published by the National Institute of Standards and Technology. Tennessee's Information Protection Act (TIPA) provides an affirmative defense to businesses that maintain a written privacy policy which reasonably conforms to the NIST Privacy Framework. Conformance is reflected in the completeness and organization of this policy -- in what is covered and how it is managed -- not in NIST jargon on the page.

---

## 2. What We Collect and Why

We collect the minimum information needed to operate the Platform, verify identity, maintain safety, and fulfill our legal obligations. Here is what we collect and why.

### 2.1 Admission data

When you create an account, we collect:

- **Legal name.** Your real, legal name (or the name by which you are known and identified in daily life). We collect this to ensure that every member is a real, accountable person. Your legal name is not displayed publicly by default. See Section 4.
- **Email address.** Used to verify your account, send you security notifications, and communicate about your membership.
- **Age attestation.** We record a timestamp confirming that you submitted a date of birth indicating you are 18 or older. We do not retain the date of birth itself -- only the confirmation that the check was passed and when.
- **@handle.** The public name you choose for your account. This is what other members see when you post.

### 2.2 Account and profile data

Once your account is active, we maintain:

- Your account settings and preferences, including any choice to display your legal name publicly
- Your profile content, such as a bio or profile image you choose to add
- Your follow relationships (who you follow, who follows you)
- Your account status, including membership tier, trust level, and any active enforcement actions

### 2.3 Technical and security data

We collect certain technical data automatically when you use the Platform:

- **IP addresses.** Logged at signup and on significant account activity. Used to detect ban evasion, botnet patterns, and coordinated account creation.
- **Device fingerprints.** A technical signature of your device and browser configuration. Used to detect when a banned account is attempting to re-register and to identify bot signups. Device fingerprint data is not used for tracking across other websites or for advertising.
- **Signup velocity and clustering signals.** When multiple accounts are created from the same IP range or with similar patterns in a short window, our automated pre-filter flags them for review. These signals are used solely for security purposes.
- **Authentication factors.** If you set up multi-factor authentication -- including TOTP authenticator codes or WebAuthn hardware security keys -- we store the cryptographic data needed to verify your authentication factors. Your password is never stored in a form we can read; it is stored as a one-way cryptographic hash.
- **Log data.** Standard server logs including timestamps, request paths, error codes, and referrer information.

### 2.4 Content you create publicly

When you use the Platform's public features, we collect and store:

- Posts and threaded replies you publish
- Reactions, likes, or other interactions you make with other members' content
- Reports you file about content or members

No image upload currently exists on the platform. When public image upload is added, images will be collected and processed as described in Section 6.

### 2.5 Direct messages

Direct messages are end-to-end encrypted. When you use the direct messaging feature, we store:

- **Message ciphertext.** Your messages are stored in encrypted form that the platform cannot read. Only you and the recipient hold the keys needed to decrypt them.
- **Message metadata.** Timestamps and the account identifiers of sender and recipient. This metadata is not encrypted and is readable by the platform.

**Please read Section 5 before using direct messages.** It explains what end-to-end encryption means for your privacy and how reporting works.

### 2.6 Moderation and enforcement data

We maintain records necessary to operate a safe platform:

- Reports filed by members about content or other members
- Moderation decisions and the basis for each decision
- Enforcement actions taken, including warnings, suspensions, and bans
- A tamper-evident, hash-chained audit log of administrative actions on the Platform

The audit log is designed so that any alteration to a past record breaks the chain and is detectable. This protects members and the Platform by creating a reliable record of what was decided and when.

---

## 3. How We Use Your Information

We use the information we collect for the following purposes:

**Operating the Platform.** Providing the services you signed up for: posts, replies, follows, direct messages, and all other Platform features.

**Verifying identity and preventing fraud.** Confirming that applicants are real people, detecting duplicate accounts, and blocking banned accounts from re-registering.

**Safety and trust and safety enforcement.** Investigating reports, making moderation decisions, and maintaining the audit log.

**CSAM compliance.** No image upload currently exists on the platform. When public image upload is added, every image will be automatically scanned for child sexual abuse material and we will fulfill our mandatory reporting obligations. See Section 6. Under end-to-end encryption, direct message images (if DM image upload is ever enabled) cannot be proactively scanned; this limitation and its implications are described in Section 6.

**Security.** Detecting and responding to unauthorized access, attacks, and abuse.

**Communications.** Sending you account-related emails -- verification, security alerts, and moderation decisions. We do not send marketing emails without your separate consent.

**Legal compliance.** Fulfilling obligations under applicable law, including responding to valid legal process and preserving evidence as required.

**Improving the Platform.** Understanding how the Platform is used so we can fix problems and improve it. We use aggregate, non-identifying data for this purpose wherever possible.

We do not sell your personal information. We do not use your information for behavioral advertising. We do not build advertising profiles.

---

## 4. Your Legal Name: Collected, Not Displayed

This section deserves its own plain-English explanation because it is a deliberate and important design decision.

**We collect and verify your real legal name.** Every member is a known, accountable person. This is how we prevent anonymous harassment, track ban evasion, and honor our safety mission. The Community Guidelines say it plainly: you are not anonymous to us.

**We do not display your legal name publicly by default.** When you post, reply, follow, or appear anywhere on the Platform, other members see your @handle. Your legal name does not appear unless you choose to show it.

**Displaying your legal name is opt-in.** You can turn it on in your account settings. You can turn it off again whenever you like.

**Why this matters.** A member who is hiding from a stalker, an abusive ex-partner, or anyone else who might find their legal name is not exposed by default. The platform knows who you are. The public does not need to. This is called pseudonymity with accountability -- and it is a safety feature, not a loophole.

Your legal name is accessible to platform administrators for the purposes described in this policy: identity verification, moderation, and legal compliance. It is not shared with other members except as described in Section 7, and it is not sold or disclosed for advertising.

---

## 5. Direct Messages: An Important Disclosure

**Please read this section. It describes something every member should understand before using direct messages.**

**Direct messages are end-to-end encrypted.**

End-to-end encryption means that only you and the recipient can read a message. Hersciety does not have the technical ability to read the content of your direct messages. Your messages are stored on our servers as ciphertext -- an encrypted form that requires keys held only on member devices to read. There are no server-side keys. We genuinely cannot look.

**What this means in practice:**

- The platform cannot read your messages. Not for routine monitoring, not for safety investigations, and not in response to a request from law enforcement -- unless a member has reported those messages (see below).
- **Reporting works differently under end-to-end encryption.** If you report a direct message, your own device -- which can read the messages -- attaches the specific messages you selected to the report. This is the only way message content reaches our moderation team. You choose exactly what you share.
- Each reported message carries a cryptographic tag that lets us verify the content is genuine: it was actually sent by the account named in the report and has not been altered. The reporter cannot fabricate a message. The sender cannot deny having sent it.
- **The platform cannot proactively scan direct messages** -- including for child sexual abuse material -- because we cannot read content we cannot decrypt. This is disclosed honestly: if you encounter CSAM in a direct message, reporting it through the platform is how you bring it to our attention. The same moderation and legal escalation process applies.
- If we receive a valid legal order requiring us to produce direct message content, we can produce only: metadata (who messaged whom, and when), the ciphertext stored on our servers (which we cannot read, and which requires member device keys to decrypt), and any evidence a member voluntarily attached to a report. We cannot produce readable message content, because we do not have it.

**At launch, direct messages are text only.** No image upload exists anywhere on the platform. Enabling images in direct messages is a separate decision that requires its own legal, safety, and technical review -- including deciding how the CSAM posture for DM images will be handled before that feature can ship. This section will be updated when that decision is made.

**This architecture is a deliberate safety choice.** The members of this platform include people who need to know their private communications cannot be read without their knowledge. End-to-end encryption provides a technical guarantee -- not just a policy promise -- that the platform cannot access DM content. We chose the design that genuinely cannot look, and we are telling you clearly so you understand what that means for both your privacy and for reporting.

We do not read your direct messages routinely. We are not monitoring conversations or reading your messages to train AI models, build profiles, or serve you content. The only time message content reaches our team is when you choose to attach it to a report.

If you share highly sensitive communications, end-to-end encryption is here. If you need the platform to be able to act on something in your inbox without your involvement, understand that under this design, we cannot -- and we think that is the right trade-off for this community.

---

## 6. CSAM Detection and Mandatory Reporting

**The Platform does not currently have image upload functionality.** No images can be posted to public feeds or sent in direct messages at this time. This section describes the platform's legal obligations and intended approach to child sexual abuse material detection, which will apply when image upload is added to the platform.

**When public image upload is added.** Every image uploaded to a public post will be automatically scanned for child sexual abuse material using hash-matching technology. A mathematical fingerprint of each uploaded image will be compared against a database of fingerprints of confirmed CSAM. The image is not "viewed" by the system; the hashes are compared. [ATTORNEY NOTE: CyberTipline registration with NCMEC must be completed before image upload ships. PhotoDNA integration and Cloudflare CSAM scanning tooling should be in place and verified before any image upload goes live.]

**Direct messages and end-to-end encryption.** Direct messages are end-to-end encrypted (see Section 5). If DM image upload is ever enabled, the platform will not be able to proactively scan DM images, because it cannot read content it cannot decrypt. DM-image CSAM can only be brought to the platform's attention through a member report. This posture is the same one held by other end-to-end encrypted messengers and is defensible under 18 U.S.C. § 2258A on the basis that the platform has no actual knowledge of content it cannot access. This must be a deliberate, documented, and attorney-reviewed decision before DM images are enabled.

**What happens when CSAM is detected (public images, once image upload exists):**

1. The content is immediately quarantined and removed from access.
2. The account is suspended pending investigation.
3. Evidence is preserved.
4. A report is filed with the National Center for Missing and Exploited Children (NCMEC) via the CyberTipline, as required by 18 U.S.C. § 2258A as amended by the REPORT Act. NCMEC may forward the report to law enforcement.

**Evidence preservation.** Federal law (18 U.S.C. § 2258A, as amended by the REPORT Act) requires electronic service providers to preserve CSAM reports and associated evidence for a minimum of one year. We will comply with this requirement when it applies. Evidence related to a CSAM report is retained for at least one year regardless of account deletion requests.

**No warnings.** An account found to have uploaded CSAM is immediately and permanently terminated. There is no appeal for this outcome.

---

## 7. How We Share Your Information

We share personal information only as described in this section.

### 7.1 Service providers

We use third-party vendors to operate the Platform. Each vendor receives only the data necessary for the service it provides. The table below lists our current service providers.

| Provider | What they do | Data they receive |
|---|---|---|
| Supabase | Database, authentication, and real-time infrastructure | All account data, content, and message ciphertext stored in the database; authentication credentials |
| Vercel | Application hosting and delivery | Request logs, IP addresses, application traffic |
| Cloudflare | CDN and email routing | Domain traffic, email routing metadata |
| Resend | Transactional email delivery | Email addresses, email content (verification, notifications, alerts) |

We do not sell personal information to any of these vendors or any other party. These vendors process data on our behalf, under agreements that restrict them to using data only for the services they provide to us.

[ATTORNEY NOTE: Data Processing Agreements (DPAs) should be in place with each vendor in this table before personal data flows to them. Supabase, Cloudflare, and Resend offer standard DPAs; confirm execution before launch. If additional vendors are added -- for example, for image scanning, media storage, or phone verification -- DPAs should be negotiated before those integrations go live and this table must be updated.]

### 7.2 Law enforcement and legal process

We may disclose personal information to law enforcement, courts, or other government authorities when:

- We are required to by a valid legal order, subpoena, warrant, or court order
- We are responding to a legal obligation, such as the CSAM mandatory reporting obligation described in Section 6
- We believe in good faith that disclosure is necessary to prevent imminent harm to a specific person
- We are required to cooperate with an official investigation

We will notify you of legal demands for your information where we are legally permitted to do so.

### 7.3 NCMEC

As described in Section 6, we are required by federal law to report CSAM detections to the National Center for Missing and Exploited Children. Reports include account information, preserved evidence, and circumstances of the detection.

### 7.4 Safety of others

In limited circumstances -- specifically, where we believe there is a credible, imminent threat to a specific person's physical safety -- we may share information with appropriate parties without a legal order.

### 7.5 Business transfers

If Curry Co LLC is acquired, merged, or transfers all or substantially all of its assets, personal information may be transferred as part of that transaction. We will notify affected members and give them an opportunity to delete their accounts before any such transfer occurs.

### 7.6 With your consent

We share personal information for any other purpose only with your explicit, informed consent.

---

## 8. Data Retention

This section describes how long we keep different categories of information. Retention periods have been set by the owner and are stated below. Attorney review notes are marked; do not publish those brackets.

**Account profile data.** We retain your account data -- legal name, email address, @handle, and profile content -- for as long as your account is active. If you delete your account, we delete or anonymize this information within **30 days**.

**Public content.** Posts and replies you publish publicly are retained while your account is active. On account deletion, **public content is deleted together with the account**.

**Direct messages.** Direct messages are end-to-end encrypted and stored on our servers only as ciphertext we cannot read. **When you delete your account, that ciphertext is deleted.** Undelivered ciphertext -- messages that never reached the recipient -- is purged at the same time. Note that messages you sent remain on the recipient's device; deleting your account does not remove your sent messages from their devices.

**Technical and security data.** IP addresses, device fingerprints, and signup signals are retained for **90 days**. After that period, these records are deleted unless they are tied to an active investigation or enforcement action.

**Moderation records.** Records of reports, moderation decisions, and enforcement actions are retained for **2 years** from the date of the record. [ATTORNEY NOTE: Confirm this period is sufficient for applicable statutes of limitations in the jurisdictions where the platform operates.]

**CSAM reports and evidence.** Evidence related to a CSAM detection and the corresponding NCMEC report is retained for a minimum of one year, as required by 18 U.S.C. § 2258A as amended by the REPORT Act. We may retain such evidence longer if required by law enforcement or an active investigation.

**Audit log.** The tamper-evident administrative audit log is archived to write-protected storage. Current architecture provides for retention of this log for seven years. [ATTORNEY NOTE: Confirm that the retention period for audit logs is appropriate and consistent with applicable legal obligations.]

**Ban-evasion signals.** When an account is permanently banned, certain signals -- including device fingerprints and account associations used to identify ban evasion -- are retained for **2 years** from the date of the permanent ban. These signals are retained independently of account deletion to prevent ban evasion. [ATTORNEY NOTE: Confirm this retention period and the purpose limitation are appropriate under applicable privacy law, particularly for members in California.]

**Data retained after account deletion.** Some data is retained even after you delete your account. Specifically:

- CSAM reports and associated evidence (statutory requirement, minimum one year)
- Audit log records relating to your account (seven years per current architecture)
- Ban-evasion signals if your account was permanently banned (2 years from the ban date)
- Any information subject to a legal hold, active investigation, or court order

When we retain data after account deletion, we do so only for the specific purposes described and do not use it for any other purpose.

---

## 9. Security

We implement technical and organizational measures designed to protect personal information against unauthorized access, disclosure, and loss. Here is what we actually do.

**Encryption in transit.** All communication between your browser and the Platform is encrypted using TLS. We do not serve the Platform over unencrypted connections.

**Encryption at rest.** Data stored in our database is encrypted at rest by our infrastructure provider (Supabase/PostgreSQL).

**Authentication security.** Passwords are never stored in readable form -- only as one-way cryptographic hashes. We support and encourage multi-factor authentication using TOTP authenticator apps and WebAuthn hardware security keys (such as YubiKeys). High-privilege administrator access requires multi-factor authentication.

**Access controls.** Access to personal data within our systems is limited by role. Only accounts with explicit administrative permissions can access member data, and those permissions are enforced at the database layer, not only in application code. The permission system is designed so that even the platform's own application server cannot grant itself elevated privileges -- role grants require a deliberate administrative action that is logged.

**Audit logging.** Administrative actions are recorded in a tamper-evident, hash-chained log. Each record is cryptographically linked to the one before it, so any alteration to a past record is detectable.

**Image handling (when image upload exists).** When public image upload is added to the platform, every image will have its EXIF metadata -- including GPS location -- stripped before storage. Location data from photos will not enter our systems. Images will land in a staging area, undergo processing (EXIF strip, CSAM scan, encoding), and only then move to the serving infrastructure. Raw, unprocessed images will not be served.

**What we do not claim.** No system connected to the internet is perfectly secure. We do not guarantee that data will never be compromised. We do not use the phrase "military-grade encryption" or any other marketing language that overstates what security measures can promise. If a security incident occurs that affects your personal information, we will notify you as required by applicable law.

---

## 10. Your Rights and Choices

**10.1 Access.** You may request a copy of the personal information we hold about you. We will provide it in a commonly used, machine-readable format where technically feasible. Submit your request to legal@unitedfeminist.com.

**10.2 Correction.** If personal information we hold about you is inaccurate or incomplete, you may request that we correct it. You can update most profile information directly in your account settings. For information you cannot update yourself (such as your verified legal name), contact legal@unitedfeminist.com.

**10.3 Deletion.** You may request deletion of your personal information by closing your account through your account settings or by contacting support@unitedfeminist.com. We will delete or anonymize your account data within the timeframe described in Section 8. Note that some data is retained after deletion as described in that section -- we will tell you what we cannot delete and why.

**10.4 Data portability.** You may request a copy of the content you have created on the Platform (posts, replies) in a portable format. Submit your request to legal@unitedfeminist.com.

**10.5 Opt out of name display.** You can choose not to display your legal name publicly at any time through your account settings. This is the default, and you may change it back and forth as you like.

**10.6 How to submit requests.** Send privacy requests to legal@unitedfeminist.com. Include your @handle and a description of your request. We will respond within 45 days. If a request is complex or numerous, we may extend this period by an additional 45 days and will notify you of the extension.

**10.7 Non-retaliation.** Exercising your privacy rights will not result in any penalty, reduced service, or adverse treatment from us.

---

## 11. Cookies and Similar Technologies

**11.1 What we use.** The Platform uses cookies and similar technologies (including browser local storage and session identifiers) for the following purposes:

- **Authentication.** Keeping you logged in between visits. Without this, you would need to log in on every page.
- **Security.** Maintaining session integrity and detecting session hijacking.
- **Preferences.** Remembering settings you have chosen, such as your display theme.

**11.2 What we do not use.** We do not use tracking cookies or third-party advertising cookies. We do not use cookies to build behavioral profiles or to serve targeted advertising. We do not sell cookie-derived data.

**11.3 Third-party cookies.** Our infrastructure providers (including Cloudflare) may set cookies related to CDN performance and security. We do not control those cookies and they are governed by those providers' own privacy policies.

**11.4 Managing cookies.** You can configure your browser to refuse or delete cookies, but doing so will prevent you from staying logged in to the Platform.

---

## 12. California Residents

If you are a California resident, the California Consumer Privacy Act (CCPA) as amended by the California Privacy Rights Act (CPRA) gives you specific rights regarding your personal information. This section describes those rights and how to exercise them.

**12.1 Categories of personal information we collect.** In the past 12 months, we have collected personal information in the following categories as defined by the CCPA:

- **Identifiers:** real name, email address, @handle, IP address
- **Protected characteristics:** none collected as a membership criterion; members may choose to share such information in their posts or profile
- **Commercial information:** none; we do not currently charge for membership
- **Internet or other electronic network activity information:** IP addresses, device identifiers, browser information, log data, usage activity on the Platform
- **Geolocation data:** IP-derived approximate location only; no image upload exists at this time, and when it does, GPS location will be stripped from images before storage and never retained
- **Electronic messages:** direct message ciphertext (end-to-end encrypted content the platform cannot read) and message metadata (sender, recipient, timestamps)
- **Professional or employment-related information:** none collected
- **Inferences:** we do not build behavioral profiles for advertising or commercial purposes

**12.2 Purposes for collecting personal information.** See Section 3.

**12.3 How we share personal information.** See Section 7. We do not sell personal information. We do not share personal information for cross-context behavioral advertising. We do not share personal information for any purpose beyond what is described in Section 7.

**12.4 Your California rights.** California residents have the right to:

- **Know** what categories of personal information we collect, use, disclose, and share
- **Access** specific pieces of personal information we hold about you
- **Delete** personal information we hold about you, subject to exceptions
- **Correct** inaccurate personal information
- **Opt out of sale or sharing** of personal information -- note that we do not sell or share personal information for advertising, so this right is already satisfied by our practices
- **Limit use of sensitive personal information** -- we collect certain sensitive personal information (real legal name, precise account identifiers). We use sensitive personal information only for the purposes described in this policy and do not use it to infer characteristics about you for advertising
- **Non-discrimination** for exercising any of these rights

**12.5 How to exercise California rights.** Submit requests to legal@unitedfeminist.com. We will verify your identity before responding and will act on verified requests within the timeframes required by California law (generally 45 days, with one possible 45-day extension).

**12.6 Authorized agents.** California residents may use an authorized agent to submit requests on their behalf. The agent must provide written proof of authorization, and we may contact you directly to verify the request.

---

## 13. Minors

**13.1 Minimum age.** Hersciety is intended for and restricted to adults 18 and older. We do not knowingly collect personal information from anyone under 18. By creating an account, you represent that you are at least 18 years old.

**13.2 Children under 13.** We do not knowingly collect personal information from children under 13. This is consistent with our obligations under the Children's Online Privacy Protection Act (COPPA). If we learn that we have collected information from a child under 13, we will delete that information immediately.

**13.3 Accounts discovered to belong to minors.** If we discover or are credibly informed that an account belongs to a person under 18, we will immediately suspend and terminate that account and delete associated personal information, subject to any evidence preservation obligations triggered by the account's activity (such as CSAM-related evidence preservation, which is a federal statutory obligation that cannot be overridden by a deletion request).

**13.4 How to report.** If you believe a member of the Platform is under 18, please report it to safety@unitedfeminist.com.

---

## 14. Changes to This Policy

We may update this Privacy Policy from time to time. When we make material changes, we will:

- Post the updated policy at hersciety.com/privacy-policy with a new "Last Updated" date
- Send an in-app notification
- For changes that significantly affect your rights or how we use your data, send an email to the address on your account at least 30 days before the changes take effect

Your continued use of the Platform after the effective date of an updated policy constitutes acceptance of that policy. If you do not accept the updated policy, you must stop using the Platform and close your account.

We will not make changes to this policy that reduce your rights with respect to data already collected without providing the 30-day advance notice described above.

---

## 15. Contact

For questions, requests, or concerns about this Privacy Policy or our data practices:

**Email:** legal@unitedfeminist.com

**Mail:**
Curry Co LLC
Attn: Privacy
466 E Broadway Blvd
Jefferson City, TN 37760

We aim to respond to all inquiries within 45 days.

---

*Hersciety*
*Operated by: Curry Co LLC*
*466 E Broadway Blvd, Jefferson City, TN 37760*
*legal@unitedfeminist.com*
