import 'dart:math' as math;

/// Fun lines in Malayalam / Manglish, edited from the web dashboard. `{n}` = days left, `{name}` = first name.
class FunLines {
  const FunLines(this.bySlot);
  final Map<String, List<String>> bySlot;

  /// Used until the server answers (and in the demo): the same lines the database starts with.
  static const defaults = FunLines({
    'welcome': [
      'Vouby-lekku swagatham! Oru chai edukkam, ennitt nammukku parichayappedam ☕',
      'Kerala-yude ishtam ellaam ivide. Nalla oru aal ninakku vendi kaathirikkunnu 💛',
      'Adipoli! Profile onnu polichu vechaal match onnu kittum, urappu 😉',
    ],
    'tip': [
      'Oru nalla photo + oru nalla bio = pakuthi joli kazhinju 📸',
      'Aadyam “Hi” maathram vendaa. Oru chodyam chodikku, chaya pole 😄',
    ],
    'call_locked': [
      'Aadyam onnu parichayappedu, ennitt vilikkaam. {n} divasam koodi kshamikku 😄',
      'Thidukkam venda! Vilikkaan {n} divasam koodi. Appo vare chat cheyyu ☕',
    ],
    'call_ready': ['Ini vilikkaam! Randu perum parichayappettu, ippo oru call aakaam 📞'],
    'call_started': ['Oru chiriyode thudangaam 😊'],
    'empty_chat': ['Oru “Hi” ayakku, baakki njan nokkaam 😄'],
  });

  /// One line for [slot] (stable for a given [seed]), with the placeholders filled in. Empty when the slot has none.
  String pick(String slot, {int? n, String? name, int seed = 0}) {
    final lines = bySlot[slot] ?? defaults.bySlot[slot] ?? const [];
    if (lines.isEmpty) return '';
    var t = lines[math.Random(seed).nextInt(lines.length)];
    if (n != null) t = t.replaceAll('{n}', '$n');
    if (name != null) t = t.replaceAll('{name}', name);
    return t;
  }

  static FunLines fromRows(List<dynamic> rows) {
    final m = <String, List<String>>{};
    for (final r in rows) {
      final row = (r as Map).cast<String, dynamic>();
      (m[row['slot'] as String] ??= []).add(row['text'] as String);
    }
    return m.isEmpty ? defaults : FunLines(m);
  }
}
