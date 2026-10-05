# Herciety — Privacy Policy

---

## ⚠️ ATTORNEY REVIEW REQUIRED BEFORE PUBLICATION

**This is a comprehensive draft, not legal advice, and not a substitute for qualified legal counsel.**

Herciety operates an open-membership social platform for adults that handles user-generated content including images, operates a direct-messaging system with photo upload, conducts automated image scanning for child sexual abuse material, collects and verifies real legal names while protecting their public display, and uses technical signals including device fingerprints and IP addresses for safety and fraud prevention. Before this Privacy Policy is published, the owner must have it reviewed by a lawyer who is:

- Licensed to practice in Tennessee and familiar with applicable state, federal, and (when EU/UK launch occurs) international law
- Knowledgeable about data protection law including the California Consumer Privacy Act and its amendments (CCPA/CPRA), applicable state privacy statutes, and the FTC Act Section 5 unfair and deceptive acts standard
- Familiar with CSAM mandatory reporting obligations under 18 U.S.C. § 2258A as amended by the REPORT Act
- Aware of the NIST Privacy Framework (Version 1.0, January 2020) and its role in Tennessee's TIPA affirmative defense
- Experienced with social platform data practices and trust-and-safety compliance

**Specific areas of elevated legal risk on this platform that require attorney attention:**
1. The collection and verification of real legal names alongside pseudonymous public display -- confirm that the collection, storage, and limited-disclosure design is appropriately documented and that the opt-in display mechanism is clearly communicated and technically implemented before launch
2. CSAM reporting and evidence preservation obligations under 18 U.S.C. § 2258A -- confirm CyberTipline registration is complete and that the one-year preservation requirement is correctly implemented before any image upload feature is live
3. Device fingerprinting and IP retention -- confirm that the purposes and retention periods described here are accurate and sufficient under applicable law, including CCPA
4. All bracketed items in this document -- these represent open decisions that must be made before publication; do not publish with brackets remaining
5. California CCPA/CPRA compliance -- confirm the rights described in Section 12 are complete and accurate, and confirm whether the platform meets the statutory thresholds that trigger the full CPRA regime
6. Data Processing Agreements with service providers -- see Section 7 for the list of vendors; DPAs should be in place before personal data flows to any of them
7. Retention periods -- every bracketed retention period in Section 8 must be decided by the owner, reviewed by counsel, and technically implemented before publication

Do not publish this Privacy Policy without counsel review.

---

*Effective date: October 1, 2026*
*Last updated: October 1, 2026*

This Privacy Policy describes how Curry Co LLC ("Company," "we," "us," or "our") collects, uses, stores, and shares personal information when you use Herciety, the social platform available at herciety.com (the "Platform"). It also describes your rights and how to exercise them.

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

**1.1 Who we are.** Herciety is operated by Curry Co LLC, a Tennessee limited liability company. Our mailing address is 466 E Broadway Blvd, Jefferson City, TN 37760. Privacy questions and requests can be sent to legal@unitedfeminist.com.

**1.2 What this platform does.** Herciety is a text-first social platform designed as a safe space for women and their allies. Members post publicly, reply in threads, follow each other, and send direct messages including photos. Membership is fully open -- anyone who agrees to our Terms of Service and is 18 or older can create an account. Because both the platform's safety mission and our legal obligations require it, we collect and verify the real identity of every member while giving members control over what the public sees.

**1.3 Geographic scope.** The Platform currently serves members in the United States only. This policy is written for that context. If we expand to the European Union, the United Kingdom, or other jurisdictions, this policy will be updated and reviewed before that expansion occurs. Nothing in this policy creates rights under the GDPR or UK GDPR.

**1.4 NIST Privacy Framework.** This policy is structured to reasonably conform to the NIST Privacy Framework, Version 1.0 (January 2020), published by the National Institute of Standards and Technology. Tennessee's Information Protection Act (TIPA) provides an affirmative defense to businesses that maintain a written privacy policy which reasonably conforms to the NIST Privacy Framework. Conformance is reflected in the completeness and organization of this policy -- in what is covered and how it is managed -- not in NIST jargon on the page.

---

## 2. What We Collect and Why

We collect the minimum information needed to operate the Platform, verify identity, maintain safety, and fulfill our legal obligations. Here is what we collect and why.

### 2.1 Admission data

When you apply for membership, we collect:

- **Legal name.** Your real, legal name (or the name by which you are known and identified in daily life). We collect this to ensure that every member is a real, accountable person. Your legal name is not displayed publicly by default. See Section 4.
- **Email address.** Used to verify your account, send you security notifications, and communicate about your membership.
- **Phone number.** Used to verify that you are a real person and to detect duplicate accounts. We use Twilio to verify that the number is valid and not associated with a high-risk VOIP or prepaid service.
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
- Images you upload to public posts
- Reactions, likes, or other interactions you make with other members' content
- Reports you file about content or members

**EXIF metadata, including GPS location, is stripped from every image at upload before it reaches storage.** This is a deliberate privacy protection. Location data from your photos never enters our systems.

### 2.5 Direct messages

When you use the direct messaging feature, we store:

- The text content of your messages
- Images you send in direct messages
- Message metadata, including timestamps and read receipts

**Please read Section 5 before using direct messages.** It contains an important disclosure about how DM content is handled that every member should understand.

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

**CSAM detection.** Scanning images for child sexual abuse material and fulfilling our mandatory reporting obligations. See Section 6.

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

**Direct messages are not end-to-end encrypted.**

End-to-end encryption would mean that only you and the recipient could read a message, and the platform would have no technical ability to see its content. Herciety does not provide that. Your direct messages -- text and images -- are stored on our servers in a form that the platform can access.

**What this means in practice:**

- If you report a direct message as abusive, our moderation team can read the content of that message to investigate the report. The Terms of Service describe this in Section 7.4.
- Platform administrators can technically access DM content when investigating credible safety concerns.
- **All images sent in direct messages are automatically scanned for child sexual abuse material** using the same process applied to public images. This scanning is automated hash-matching -- no human reviews your DM images as part of the scanning process. But if a match is detected, staff will be involved in the response. See Section 6.
- If we receive a valid legal order requiring us to produce DM content, we are required to comply.

**We do not read your direct messages routinely.** We are not monitoring conversations or reading your messages to train AI models, build profiles, or serve you content. Access to DM content happens for the specific purposes described above -- reports, credible safety investigations, CSAM response, and legal obligations -- and is logged in the audit record.

**This architecture is a deliberate safety choice.** A platform built for survivors of harassment and stalking needs the ability to investigate when a member reports that someone is threatening them in their inbox. End-to-end encryption eliminates that ability. We chose the design that can respond to reports over the design that cannot. We are telling you clearly so you can make an informed choice about what you put in a direct message.

If you share highly sensitive information in direct messages, understand that the platform can access it under the circumstances described above. For communications that require stronger confidentiality, use a dedicated end-to-end encrypted messaging service outside of Herciety.

---

## 6. CSAM Detection and Mandatory Reporting

The Platform scans every image uploaded to it -- public posts and direct messages -- for child sexual abuse material (CSAM). Here is how that works and what happens when something is detected.

**How scanning works.** When you upload an image, it is checked against a database of hash values (digital fingerprints) of known illegal images. This is automated hash-matching: a mathematical fingerprint of your image is compared against fingerprints of confirmed CSAM. The image itself is not "viewed" by the system; the hashes are compared. This technology is provided by Cloudflare's CSAM scanning tool. Microsoft PhotoDNA integration is pending and, when active, will be added as an additional layer. [NOTE: PhotoDNA integration not yet active as of the effective date of this policy; this section will be updated when active.]

**What happens on a match.** If an image matches a known-CSAM hash:

1. The content is immediately quarantined and removed from access.
2. The account is suspended pending investigation.
3. Evidence is preserved.
4. A report is filed with the National Center for Missing and Exploited Children (NCMEC) via the CyberTipline, as required by 18 U.S.C. § 2258A as amended by the REPORT Act. NCMEC may forward the report to law enforcement.

**Evidence preservation.** Federal law (18 U.S.C. § 2258A, as amended by the REPORT Act) requires electronic service providers to preserve CSAM reports and associated evidence for a minimum of one year. We comply with this requirement. Evidence related to a CSAM report is retained for at least one year regardless of account deletion requests.

**No warnings.** An account found to have uploaded CSAM is immediately and permanently terminated. There is no appeal for this outcome.

---

## 7. How We Share Your Information

We share personal information only as described in this section.

### 7.1 Service providers

We use third-party vendors to operate the Platform. Each vendor receives only the data necessary for the service it provides. The table below lists our current service providers.

| Provider | What they do | Data they receive |
|---|---|---|
| Supabase | Database, authentication, and real-time messaging infrastructure | All account data, content, and messages stored in the database; authentication credentials |
| Vercel | Application hosting and delivery | Request logs, IP addresses, application traffic |
| Cloudflare | CDN, media storage (R2), email routing, and CSAM image scanning | Uploaded images, domain traffic, email routing metadata |
| Amazon Web Services | Tamper-proof audit log archival (S3 Object Lock) | Audit log records |
| Resend | Transactional email delivery | Email addresses, email content (verification, notifications, alerts) |
| Twilio | Phone number verification | Phone numbers submitted at signup |
| Microsoft PhotoDNA | CSAM image hash-matching | Image hash values (pending integration; not yet active) |
| Hive Moderation | Automated content classification for moderation | Images and text content submitted for moderation review (pending integration; not yet active) |

We do not sell personal information to any of these vendors or any other party. These vendors process data on our behalf, under agreements that restrict them to using data only for the services they provide to us.

[ATTORNEY NOTE: Data Processing Agreements (DPAs) should be in place with each vendor in this table before personal data flows to them. Supabase, Cloudflare, AWS, Resend, and Twilio offer standard DPAs; confirm execution before launch. Microsoft PhotoDNA and Hive Moderation DPAs should be negotiated before those integrations go live.]

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

This section describes how long we keep different categories of information. Where a retention period depends on a decision that has not yet been made, we have inserted a bracketed placeholder. All bracketed items must be resolved before this policy is published.

**Account profile data.** We retain your account data -- legal name, email address, phone number, @handle, and profile content -- for as long as your account is active. If you delete your account, we delete or anonymize this information within [RETENTION PERIOD NOT YET DECIDED -- owner must set a specific timeframe; 30 days is a common standard; attorney should confirm this is reasonable under applicable law].

**Public content.** Posts, replies, and images you publish publicly are retained while your account is active. On account deletion, public content is [RETENTION PERIOD NOT YET DECIDED -- owner must decide: deleted immediately, retained for a brief wind-down period, or retained for archival purposes; if retained after deletion, this policy must explain why and for how long].

**Direct messages.** Message content and images are retained while both parties' accounts are active. On account deletion by either party, [RETENTION PERIOD NOT YET DECIDED -- owner must decide and this section must accurately reflect the technical implementation].

**Technical and security data.** IP addresses, device fingerprints, and signup signals are retained for [RETENTION PERIOD NOT YET DECIDED -- owner must set this; a common range for security purposes is 90 days to 2 years; attorney should advise on what is defensible under CCPA and applicable state law].

**Moderation records.** Records of reports, moderation decisions, and enforcement actions are retained for [RETENTION PERIOD NOT YET DECIDED -- these records may be needed in litigation and should be retained long enough to cover the applicable statute of limitations; attorney should advise].

**CSAM reports and evidence.** Evidence related to a CSAM detection and the corresponding NCMEC report is retained for a minimum of one year, as required by 18 U.S.C. § 2258A as amended by the REPORT Act. We may retain such evidence longer if required by law enforcement or an active investigation.

**Audit log.** The tamper-evident administrative audit log is archived to write-protected storage. Current architecture provides for retention of this log for seven years. [ATTORNEY NOTE: Confirm that the retention period for audit logs is appropriate and consistent with applicable legal obligations.]

**Ban-evasion signals.** When an account is permanently banned, certain signals -- including device fingerprints and account associations used to identify ban evasion -- are retained [RETENTION PERIOD NOT YET DECIDED -- the purpose of retaining these signals is to enforce bans; if they are deleted on account deletion, ban evasion becomes trivially easy; owner and counsel should decide on an appropriate period].

**Data retained after account deletion.** Some data is retained even after you delete your account. Specifically:

- CSAM reports and associated evidence (statutory requirement, minimum one year)
- Audit log records relating to your account (seven years per current architecture)
- Ban-evasion signals if your account was permanently banned (period TBD, as above)
- Any information subject to a legal hold, active investigation, or court order

When we retain data after account deletion, we do so only for the specific purposes described and do not use it for any other purpose.

---

## 9. Security

We implement technical and organizational measures designed to protect personal information against unauthorized access, disclosure, and loss. Here is what we actually do.

**Encryption in transit.** All communication between your browser and the Platform is encrypted using TLS. We do not serve the Platform over unencrypted connections.

**Encryption at rest.** Data stored in our database and object storage is encrypted at rest by our infrastructure providers (Supabase/PostgreSQL, Cloudflare R2, AWS S3).

**Authentication security.** Passwords are never stored in readable form -- only as one-way cryptographic hashes. We support and encourage multi-factor authentication using TOTP authenticator apps and WebAuthn hardware security keys (such as YubiKeys). High-privilege administrator access requires multi-factor authentication.

**Access controls.** Access to personal data within our systems is limited by role. Only accounts with explicit administrative permissions can access member data, and those permissions are enforced at the database layer, not only in application code. The permission system is designed so that even the platform's own application server cannot grant itself elevated privileges -- role grants require a deliberate administrative action that is logged.

**EXIF stripping.** Every image uploaded to the Platform has its EXIF metadata -- including GPS location -- stripped before it is stored. Location data from your photos does not enter our system.

**Staged media handling.** Uploaded images land in a staging area, undergo processing (EXIF strip, CSAM scan, encoding), and only then move to the serving infrastructure. Raw, unprocessed images are never served.

**Audit logging.** Administrative actions are recorded in a tamper-evident, hash-chained log. Each record is cryptographically linked to the one before it, so any alteration to a past record is detectable.

**What we do not claim.** No system connected to the internet is perfectly secure. We do not guarantee that data will never be compromised. We do not use the phrase "military-grade encryption" or any other marketing language that overstates what security measures can promise. If a security incident occurs that affects your personal information, we will notify you as required by applicable law.

---

## 10. Your Rights and Choices

**10.1 Access.** You may request a copy of the personal information we hold about you. We will provide it in a commonly used, machine-readable format where technically feasible. Submit your request to legal@unitedfeminist.com.

**10.2 Correction.** If personal information we hold about you is inaccurate or incomplete, you may request that we correct it. You can update most profile information directly in your account settings. For information you cannot update yourself (such as your verified legal name), contact legal@unitedfeminist.com.

**10.3 Deletion.** You may request deletion of your personal information by closing your account through your account settings or by contacting support@unitedfeminist.com. We will delete or anonymize your account data within the timeframe described in Section 8. Note that some data is retained after deletion as described in that section -- we will tell you what we cannot delete and why.

**10.4 Data portability.** You may request a copy of the content you have created on the Platform (posts, replies, images you uploaded) in a portable format. Submit your request to legal@unitedfeminist.com.

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

- **Identifiers:** real name, email address, phone number, @handle, IP address
- **Protected characteristics:** none collected as a membership criterion; members may choose to share such information in their posts or profile
- **Commercial information:** none; we do not currently charge for membership
- **Internet or other electronic network activity information:** IP addresses, device identifiers, browser information, log data, usage activity on the Platform
- **Geolocation data:** IP-derived approximate location only; GPS location is explicitly stripped from images and never collected
- **Electronic messages:** direct message content and images
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

**13.1 Minimum age.** Herciety is intended for and restricted to adults 18 and older. We do not knowingly collect personal information from anyone under 18. By creating an account, you represent that you are at least 18 years old.

**13.2 Children under 13.** We do not knowingly collect personal information from children under 13. This is consistent with our obligations under the Children's Online Privacy Protection Act (COPPA). If we learn that we have collected information from a child under 13, we will delete that information immediately.

**13.3 Accounts discovered to belong to minors.** If we discover or are credibly informed that an account belongs to a person under 18, we will immediately suspend and terminate that account and delete associated personal information, subject to any evidence preservation obligations triggered by the account's activity (such as CSAM-related evidence preservation, which is a federal statutory obligation that cannot be overridden by a deletion request).

**13.4 How to report.** If you believe a member of the Platform is under 18, please report it to safety@unitedfeminist.com.

---

## 14. Changes to This Policy

We may update this Privacy Policy from time to time. When we make material changes, we will:

- Post the updated policy at herciety.com/privacy-policy with a new "Last Updated" date
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

*Herciety*
*Operated by: Curry Co LLC*
*466 E Broadway Blvd, Jefferson City, TN 37760*
*legal@unitedfeminist.com*
