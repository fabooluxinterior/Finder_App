import '../../models/support.dart';

/// Help Center answers. Written for how Vouby actually works; keep in sync
/// when features change. No external AI service is used.
class Faq {
  const Faq(this.question, this.answer);
  final String question;
  final String answer;
}

class FaqCategory {
  const FaqCategory(this.title, this.support, this.items);
  final String title;

  /// Pre-selected category when "Contact support" is tapped from here.
  final SupportCategory support;
  final List<Faq> items;
}

const faqCategories = <FaqCategory>[
  FaqCategory('Account and profile', SupportCategory.account, [
    Faq(
      'How do I edit my profile?',
      'Go to You → Edit profile. You can change your photos (4 to 6), prompts, interests, profession and other details. '
          'Changes save as you go.',
    ),
    Faq(
      'Why can’t I change my date of birth?',
      'Your birthdate is locked once saved, so ages on Vouby stay honest. If it was entered wrongly, contact support '
          'with the details and we’ll help.',
    ),
    Faq(
      'How do I get the verified badge?',
      'Go to You → Get verified and take a quick selfie copying the pose shown. Our team compares it with your profile '
          'photo. The selfie is deleted 30 days after review.',
    ),
    Faq(
      'How do I delete my account?',
      'Go to You → Security → Delete account. Your profile, photos and messages are removed. Some safety records are kept '
          'for a limited time as explained in the Privacy Policy.',
    ),
  ]),
  FaqCategory('Discovery and matching', SupportCategory.discovery, [
    Faq(
      'How do I choose who I see?',
      'Go to You → Settings → Discovery preferences and choose Men, Women or Everyone and an age range (18 and over). '
          'It works both ways: you see people who match your choice and who are also looking for someone like you.',
    ),
    Faq(
      'How do requests work?',
      'Swipe right or tap Request on someone’s card. If they accept, you’re connected and chat opens. Sending requests '
          'is free.',
    ),
    Faq(
      'Why do Suggestions stop for the day?',
      'You get a limited number of new suggestions each day so every profile gets a fair look. New ones arrive tomorrow; '
          'Discover is always open.',
    ),
    Faq(
      'Why did someone disappear from my deck?',
      'People you passed come back after 7 days. Profiles can also be hidden if the person paused, blocked you, or is '
          'under review by our safety team.',
    ),
  ]),
  FaqCategory('Chat and messaging', SupportCategory.chat, [
    Faq(
      'When can I chat with someone?',
      'Chat opens once a request is accepted. Messaging is part of Fast-Track or your 7-day free trial.',
    ),
    Faq(
      'Can I send photos and voice notes?',
      'Yes. Tap the photo or microphone button in a chat. Photos are compressed on your phone and, like messages and '
          'voice notes, are end-to-end encrypted: only you and the other person can open them.',
    ),
    Faq(
      'What happens to my chats when my trial ends?',
      'Nothing is deleted. Your matches, messages and photos are kept. Chat pauses until you get Fast-Track, then '
          'everything is there again.',
    ),
  ]),
  FaqCategory('Subscription and payments', SupportCategory.subscription, [
    Faq(
      'What is the 7-day free trial?',
      'New accounts get Fast-Track free for 7 days (168 hours) once setup is finished: see who sent you requests and chat. '
          'No card is needed and nothing is charged when it ends. You get reminders 24 hours before it ends and when it ends.',
    ),
    Faq(
      'How much is Fast-Track?',
      '₹79 a month (about ₹2.63 a day), billed through Google Play. You’re charged only after you confirm in Google Play, '
          'and you can cancel any time in Google Play → Subscriptions.',
    ),
    Faq(
      'I paid but Fast-Track isn’t active.',
      'Open the Fast-Track sheet and tap Restore purchase while signed in to the same Google account. If it still '
          'isn’t active after a few minutes, contact support with the Google Play order number.',
    ),
  ]),
  FaqCategory('Privacy and security', SupportCategory.privacy, [
    Faq(
      'Who can see my phone number or email?',
      'No one. They’re never shown on your profile, and phone numbers, @handles and links are blocked in names, bios '
          'and requests.',
    ),
    Faq(
      'Are my messages private?',
      'Messages, voice notes and photos are end-to-end encrypted on your device. Vouby’s servers store only scrambled '
          'data and can’t read them. If you report someone, only the messages you select are shared, and only after you '
          'confirm.',
    ),
    Faq(
      'How do I secure my account?',
      'Go to You → Security to see signed-in devices, sign out others, and turn on two-step verification with an '
          'authenticator app.',
    ),
  ]),
  FaqCategory('Safety and reporting', SupportCategory.safety, [
    Faq(
      'How do I report someone?',
      'Open their profile or your chat with them, tap ⋯ → Report, choose what happened and add details. In a chat you '
          'can long-press messages or photos to include them as evidence; you’ll see exactly what is shared before sending.',
    ),
    Faq(
      'Will they know I reported them?',
      'No. Reports are confidential. You can also block them at the same time so they can’t contact you.',
    ),
    Faq(
      'What happens after I report?',
      'A person on our safety team reviews every report; accounts are never banned automatically by report counts. '
          'Outcomes include a warning, limits, suspension or a ban, or the report may be dismissed if nothing breaks the '
          'rules.',
    ),
    Faq(
      'Someone is in immediate danger.',
      'Call 112 (India emergency) or the local police first. Then report the account in the app so we can act on it.',
    ),
  ]),
];
