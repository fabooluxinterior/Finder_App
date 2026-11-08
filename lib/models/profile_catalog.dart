/// Option catalogs for the profile builder. Values match the server's
/// validation (supabase/migrations/20261111000000_profile_builder.sql), so a
/// change here needs the same change there.
library;

class PromptDef {
  const PromptDef(this.id, this.category, this.question, this.tip);
  final String id;
  final String category;
  final String question;

  /// Shown under the answer field while writing.
  final String tip;
}

/// Original prompt catalog (mirrors `prompt_catalog`).
const promptCatalog = <PromptDef>[
  PromptDef(
    'p1',
    'Everyday',
    'A small thing that makes my week',
    'Name the exact thing: “filter coffee from the stall near my office”, not “coffee”.',
  ),
  PromptDef(
    'p2',
    'Everyday',
    'My most unpopular food opinion',
    'Pick a side someone could argue with. Debates make easy first messages.',
  ),
  PromptDef(
    'p3',
    'Everyday',
    'The last thing I got weirdly excited about',
    'Recent and specific beats impressive. Say when it happened.',
  ),
  PromptDef(
    'p4',
    'Plans',
    'A perfect Sunday in my city looks like',
    'Give a route: a place, a time of day, a person you’d bring.',
  ),
  PromptDef('p5', 'Plans', 'Next trip I’m quietly planning', 'Where, and the one thing you have to do there.'),
  PromptDef('p6', 'Plans', 'Ask me for a recommendation about', 'Choose a topic you can talk about for twenty minutes.'),
  PromptDef(
    'p7',
    'About me',
    'Friends would describe me as',
    'Quote a friend if you can. It sounds more like you than a list of adjectives.',
  ),
  PromptDef('p8', 'About me', 'I’m quietly competitive about', 'The smaller the thing, the better: carrom, crosswords, parking.'),
  PromptDef('p9', 'About me', 'A skill I’m learning right now', 'Say how far along you are. Beginners invite questions.'),
  PromptDef('p10', 'About me', 'I geek out about', 'Add one detail only a fan would know.'),
  PromptDef(
    'p11',
    'Connection',
    'We’ll get along if you',
    'Describe a behaviour, not a type: “reply to voice notes with voice notes”.',
  ),
  PromptDef(
    'p12',
    'Connection',
    'The way to win me over is',
    'Keep it kind and concrete. Something a stranger could actually do.',
  ),
  PromptDef('p13', 'Connection', 'A green flag I always notice', 'Pick something you’d genuinely look for on a first chat.'),
  PromptDef('p14', 'Connection', 'Let’s debate this', 'State your position in one line so they know which side to take.'),
  PromptDef('p15', 'Stories', 'The story my family won’t stop telling', 'Give the setup and leave the punchline for the chat.'),
  PromptDef('p16', 'Stories', 'Two truths and a lie', 'Make the lie believable. People love guessing.'),
];

PromptDef? promptById(String id) {
  for (final p in promptCatalog) {
    if (p.id == id) return p;
  }
  return null;
}

const promptAnswerMax = 150;
const promptsMin = 2;
const promptsMax = 3;

class Choice {
  const Choice(this.value, this.label);
  final String value;
  final String label;
}

class LifestyleField {
  const LifestyleField(this.key, this.title, this.question, this.choices);
  final String key;
  final String title;
  final String question;
  final List<Choice> choices;

  String? labelOf(String? value) {
    for (final c in choices) {
      if (c.value == value) return c.label;
    }
    return null;
  }
}

/// Stage 3 selections. Keys and values mirror `lifestyle_options()`.
const lifestyleFields = <LifestyleField>[
  LifestyleField('intention', 'Looking for', 'What are you hoping to find here?', [
    Choice('long_term', 'A long-term relationship'),
    Choice('long_term_open', 'Long-term, open to short'),
    Choice('short_term_open', 'Short-term, open to long'),
    Choice('figuring_out', 'Still figuring it out'),
    Choice('friendship', 'New friends'),
  ]),
  LifestyleField('activity', 'Exercise', 'How often do you work out?', [
    Choice('daily', 'Every day'),
    Choice('often', 'Most weeks'),
    Choice('sometimes', 'Now and then'),
    Choice('rarely', 'Rarely'),
  ]),
  LifestyleField('drinking', 'Drinking', 'Do you drink?', [
    Choice('never', 'Don’t drink'),
    Choice('socially', 'Socially'),
    Choice('regularly', 'Regularly'),
    Choice('sober', 'Sober'),
  ]),
  LifestyleField('smoking', 'Smoking', 'Do you smoke?', [
    Choice('never', 'Don’t smoke'),
    Choice('socially', 'Socially'),
    Choice('regularly', 'Regularly'),
    Choice('quitting', 'Trying to quit'),
  ]),
  LifestyleField('zodiac', 'Star sign', 'What’s your star sign?', [
    Choice('aries', 'Aries'),
    Choice('taurus', 'Taurus'),
    Choice('gemini', 'Gemini'),
    Choice('cancer', 'Cancer'),
    Choice('leo', 'Leo'),
    Choice('virgo', 'Virgo'),
    Choice('libra', 'Libra'),
    Choice('scorpio', 'Scorpio'),
    Choice('sagittarius', 'Sagittarius'),
    Choice('capricorn', 'Capricorn'),
    Choice('aquarius', 'Aquarius'),
    Choice('pisces', 'Pisces'),
  ]),
  LifestyleField('culture', 'Background', 'Which cultural background do you identify with?', [
    Choice('malayali', 'Malayali'),
    Choice('tamil', 'Tamil'),
    Choice('kannadiga', 'Kannadiga'),
    Choice('telugu', 'Telugu'),
    Choice('marathi', 'Marathi'),
    Choice('gujarati', 'Gujarati'),
    Choice('bengali', 'Bengali'),
    Choice('punjabi', 'Punjabi'),
    Choice('hindi_belt', 'North Indian'),
    Choice('northeast', 'Northeast Indian'),
    Choice('anglo_indian', 'Anglo-Indian'),
    Choice('mixed', 'Mixed'),
    Choice('other', 'Something else'),
  ]),
];

LifestyleField lifestyleField(String key) => lifestyleFields.firstWhere((f) => f.key == key);

const genders = [Choice('woman', 'Woman'), Choice('man', 'Man'), Choice('non_binary', 'Non-binary')];
String? genderLabel(String? v) => genders.where((g) => g.value == v).map((g) => g.label).firstOrNull;

const pronounOptions = ['she/her', 'he/him', 'they/them', 'she/they', 'he/they'];

const languageOptions = [
  'Malayalam',
  'English',
  'Hindi',
  'Tamil',
  'Kannada',
  'Telugu',
  'Arabic',
  'Urdu',
  'Bengali',
  'Marathi',
  'Konkani',
  'Tulu',
];
const languagesMax = 6;

class InterestCategory {
  const InterestCategory(this.title, this.tags);
  final String title;
  final List<String> tags;
}

/// Stage 4 chips. Tags are plain words (server: letters, spaces, &, ', /, -).
const interestCategories = <InterestCategory>[
  InterestCategory('Creative arts', [
    'Photography',
    'Painting',
    'Sketching',
    'Writing',
    'Poetry',
    'Film making',
    'Theatre',
    'Music production',
    'Singing',
    'Dance',
    'Kathakali',
    'Crafts',
  ]),
  InterestCategory('Food & cuisine', [
    'Street food',
    'Home cooking',
    'Baking',
    'Filter coffee',
    'Chai',
    'Biryani hunts',
    'Seafood',
    'Vegan food',
    'Cafés',
    'Toddy shops',
  ]),
  InterestCategory('Active & sports', [
    'Football',
    'Cricket',
    'Badminton',
    'Running',
    'Trekking',
    'Cycling',
    'Swimming',
    'Yoga',
    'Gym',
    'Kayaking',
    'Kalaripayattu',
  ]),
  InterestCategory('Gaming', [
    'Console games',
    'PC games',
    'Mobile games',
    'Board games',
    'Carrom',
    'Chess',
    'Card games',
    'Esports',
  ]),
  InterestCategory('Reading', [
    'Fiction',
    'Malayalam literature',
    'Poetry books',
    'History',
    'Science',
    'Comics',
    'Self-help',
    'Podcasts',
  ]),
];

const interestsMin = 5;
const interestsMax = 15;

/// Photo grid limits.
const maxPhotoSlots = 6;
const photosMin = 4;
