# Decision Record: Age Assurance

**Date:** October 2, 2026
**Author:** Curry Co LLC (United Feminist platform owner)
**Status:** Decided

---

**This is an internal decision record, not legal advice. It documents the owner's deliberate, reasoned choice on age assurance for the United Feminist platform. It does not substitute for attorney review.**

---

## The decision

Self-attestation. At signup, every applicant enters a date of birth and checks a box affirming they are 18 or older. Registration is rejected if the date of birth entered is under 18. No document verification. No facial age estimation. A device that fails the check is soft-blocked from retrying for 14 days.

This is a deliberate, informed decision -- not a default the platform drifted into. The point of this record is to show that.

---

## The legal landscape

### Federal law: no verification required here

COPPA (Children's Online Privacy Protection Act) governs collection of personal information from children under 13. It creates no proactive age-verification duty for a general-purpose 18-and-over social platform that does not target minors.

### Adult-content age-verification statutes: not applicable

Twenty-seven states have enacted laws requiring age verification for online content, following the Supreme Court's decision in *Free Speech Coalition, Inc. v. Paxton*, 606 U.S. 461 (decided June 27, 2025). Those statutes cover sites where more than one third of content is sexually explicit. United Feminist is a text-first community platform and is plainly outside their scope.

### Industry norm

Self-attestation -- a date-of-birth field at signup, plus a terms checkbox -- is the age-assurance method used by Facebook, Instagram, X, Reddit, and TikTok. It is the established industry standard for general-purpose social platforms.

### Tennessee: the reason this record exists

**Tennessee's Protecting Children from Social Media Act (Public Chapter 899 / HB 1891) took effect January 1, 2025.** It requires social media platforms to verify the age of all prospective account holders and obtain parental consent for minors. It has no size threshold. A platform with ten users is covered on the same terms as Meta.

Penalties reach $1,000 per violation. Enforcement is exclusive to the Tennessee Attorney General -- there is no private right of action.

**Curry Co LLC is a Tennessee limited liability company.** Of all fifty states, the owner's home state is one of the few with an in-force statute on exactly this question.

### Litigation status -- NetChoice v. Skrmetti

NetChoice filed suit in October 2024. The federal district court for the Middle District of Tennessee denied a preliminary injunction in June 2025, holding that NetChoice had not demonstrated sufficient irreparable harm.

On August 28, 2026, the Sixth Circuit Court of Appeals vacated that denial and remanded the case (No. 25-5660, 2-1, Judge Batchelder writing, Judge Clay dissenting). The court held that compliance costs and chilled First Amendment rights can constitute irreparable harm. It expressly did not rule on the merits.

**The law is therefore in force today with no injunction. A new preliminary injunction on remand is plausible but not certain.**

**A material fact on enforcement risk:** the record in that case shows Tennessee has not enforced the Act or sent enforcement letters to any NetChoice member -- not one, not even to Meta or Google. Enforcement risk to a small, early-stage platform is real but low.

---

## Options considered

### 1. Mandatory document verification at signup -- rejected

Requiring government ID would resolve the Tennessee statute question directly. It was rejected because:

- **Trans exclusion.** A trans member whose ID bears a deadname or mismatched gender marker would be forced to out herself to join. That is not a minor inconvenience -- it is a safety risk and a barrier that is incompatible with this platform's core commitment to trans inclusion.
- **Domestic abuse exclusion.** Withholding identity documents is a documented control tactic used by abusive partners. This platform's users include women leaving such situations. Requiring a document they may not have access to excludes people the platform specifically exists to serve.
- **Document handling.** The platform would become a holder of government identity documents, with all the security and liability exposure that creates.

These are exclusion tests, not preferences. Any mechanism that fails them is not a viable option for this platform, regardless of its compliance value.

### 2. Cropped or redacted ID images -- rejected

The idea was to collect a government ID with the name and face cropped out, limiting what the platform sees to proof-of-age information only. This was rejected because the mechanism defeats itself.

Automated authenticity checks depend on the parts that would be redacted:

- The Machine Readable Zone on passports encodes the date of birth and check digits. Cross-validating the printed date against the MRZ is the most common fraud check. Cropping removes it.
- The PDF417 barcode on the back of US driver's licenses is the primary machine-readable element. It encodes everything on the front. Cropping removes it.
- Hologram, OVI, and Dynaprint detection require the full document to template-match against genuine specimens. Cropping removes the areas where these features appear.

A cropped image cannot actually be verified. It is trivially faked in any image editor. It would also make the platform a holder of identity-document images and require untrained human review. This option does not pass either exclusion test and does not provide real verification.

### 3. Facial age estimation (Yoti or Didit) -- deferred, not rejected

Age estimation from a selfie -- no document, no identity -- is the only option that passes both exclusion tests without compromise:

- No document is needed, so it works for members who cannot safely access theirs.
- No name or gender marker is involved, so it does not out trans members.
- Vendors like Yoti delete the image immediately and retain no biometric template.

Published accuracy figures for Yoti are strong for the 13-17 age range; NIST ranked Yoti first for accuracy in that cohort in its October 2024 evaluation. Didit offers comparable technology at a published rate of $0.10 per check.

**This option was deferred, not rejected, for two reasons:**

1. **Signup conversion.** A selfie wall at the beginning of registration would substantially reduce signups on a platform growing from zero. The conversion cost is not acceptable at this stage.
2. **Biometric law exposure.** Deploying facial analysis at signup would create biometric-law exposure -- most critically under Illinois BIPA, which carries a private right of action -- for every user who signs up, rather than a small subset of users flagged for other reasons.

If the decision ever changes, the implementation is not a mandatory signup wall. It is a risk-triggered check: applied when a member is reported as a possible minor, when behavioral signals suggest underage use, or as a random audit. See the trigger conditions below.

---

## Why self-attestation was chosen

It is the only option that:

- Passes the trans-inclusion test (no document, no gender marker, no outing)
- Passes the no-documents test (no ID required from members who cannot safely access theirs)
- Costs nothing
- Is the established industry norm
- Paired with a device-level soft block, deters casual underage access

The decision is not that verification is unimportant. It is that the available verification methods each impose costs on the people this platform most needs to protect, and the marginal protective value of any of them against a determined bad actor is low -- anyone willing to use someone else's ID defeats document verification. The real value of a more rigorous method would be compliance posture, not safety. At this stage, the compliance risk is manageable and the exclusion cost is not.

---

## What would change this decision

These are the explicit triggers. If any of them materialises, the decision is revisited -- not assumed to still hold.

1. **The Tennessee law survives remand** (the district court denies a preliminary injunction a second time) **and any signal of enforcement reaches small platforms** -- a letter, a complaint, an investigation of a platform materially similar in size to United Feminist.

2. **A minor is discovered on the platform**, or any incident involving a minor occurs.

3. **The platform grows to a scale** where self-attestation is no longer a defensible posture relative to the risk profile.

If a trigger fires, the fallback is facial age estimation deployed as a **risk-triggered check** -- on a report of a suspected minor, on behavioral flags, or by random audit. Never as a mandatory signup wall.

---

## Open items

- **Tennessee counsel** should review Public Chapter 899's scope and Curry Co LLC's specific exposure under it before the platform launches to the public.
- **NetChoice v. Skrmetti, 6th Cir. No. 25-5660** should be monitored on remand. A preliminary injunction from the district court on remand would substantially reduce the Tennessee compliance pressure.

---

*This record documents the platform owner's deliberate decision as of October 2, 2026. It is planning and legal-posture material. It is not legal advice and is not a substitute for attorney review.*
