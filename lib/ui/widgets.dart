import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/logic.dart';
import '../core/theme.dart';
import '../data/store.dart';

/// White rounded card with the web app's soft border + shadow.
class CardBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? topStrip;
  const CardBox({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.topStrip});
  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: C.slate100),
        boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 24, offset: Offset(0, 12), spreadRadius: -14)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: topStrip == null ? content : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Container(height: 4, color: topStrip), content]),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Tone tone;
  final IconData? icon;
  const Pill(this.text, {super.key, this.tone = Tone.slate, this.icon});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: tone.fg), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tone.fg)),
        ]),
      );
}

class StatTile extends StatelessWidget {
  final Tone tone;
  final IconData icon;
  final String label, value;
  final String? sub;
  const StatTile({super.key, required this.tone, required this.icon, required this.label, required this.value, this.sub});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [tone.bg, Color.alphaBlend(tone.solid.withValues(alpha: .10), tone.bg)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tone.solid.withValues(alpha: .15)),
        ),
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: tone.solid, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: Colors.white, size: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 12, color: tone.fg, fontWeight: FontWeight.w600)),
              FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              if (sub != null) Text(sub!, style: const TextStyle(fontSize: 11, color: C.fg3), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      );
}

/// Two-column grid of stat tiles.
class StatGrid extends StatelessWidget {
  final List<Widget> children;
  const StatGrid(this.children, {super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (c, box) {
        final w = (box.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final ch in children) SizedBox(width: box.maxWidth < 360 ? box.maxWidth : w, child: ch)]);
      });
}

class EmptyState extends StatelessWidget {
  final String text;
  final IconData icon;
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(children: [Icon(icon, size: 42, color: C.slate400), const SizedBox(height: 10), Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.fg3))]),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Row(children: [Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))), ?trailing]),
      );
}

/// Valid / due soon / expired chip for a date.
class ExpiryChip extends StatelessWidget {
  final String? date;
  final int days;
  const ExpiryChip(this.date, {super.key, required this.days});
  @override
  Widget build(BuildContext context) {
    if (date == null || date!.isEmpty) return const Pill('غير مسجّل');
    final n = daysLeft(date!);
    if (n < 0) return Pill('منتهية منذ ${-n} يوم', tone: Tone.red);
    if (n <= days) return Pill(n == 0 ? 'تنتهي اليوم' : 'تنتهي خلال $n يوم', tone: Tone.orange);
    return Pill('سارية حتى ${fmtDate(date)}', tone: Tone.green);
  }
}

/// Worker photo from storage, or a person silhouette.
class WorkerPhoto extends StatelessWidget {
  final String? id;
  final double size;
  const WorkerPhoto(this.id, {super.key, this.size = 40});
  @override
  Widget build(BuildContext context) {
    final empty = Container(
      width: size, height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.slate400, C.fg3])),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.bottomCenter,
      child: Icon(Icons.person, size: size * .85, color: Colors.white),
    );
    if (id == null || id!.isEmpty) return empty;
    return FutureBuilder<String?>(
      future: store.fileUrl(id!),
      builder: (c, s) => s.data == null
          ? empty
          : ClipOval(child: Image.network(s.data!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => empty)),
    );
  }
}

class ProgressBar extends StatelessWidget {
  final double pct;
  final Gradient gradient;
  const ProgressBar(this.pct, {super.key, this.gradient = const LinearGradient(colors: [C.success, Color(0xFF047857)])});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: Container(
          height: 7,
          color: C.slate200,
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(widthFactor: (pct / 100).clamp(0, 1), child: Container(decoration: BoxDecoration(gradient: gradient))),
        ),
      );
}

/// Opens a stored file via a temporary signed link.
Future<void> openStoredFile(BuildContext context, Json f) async {
  final url = await store.fileUrl(str(f['id']));
  if (url == null) {
    if (context.mounted) toast(context, 'تعذّر فتح الملف', bad: true);
    return;
  }
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class FileTile extends StatelessWidget {
  final Json f;
  const FileTile(this.f, {super.key});
  @override
  Widget build(BuildContext context) {
    final t = str(f['type']);
    final icon = t.contains('pdf') ? Icons.picture_as_pdf_outlined : t.startsWith('image/') ? Icons.image_outlined : t.contains('sheet') || t.contains('excel') || t.contains('csv') ? Icons.table_chart_outlined : Icons.insert_drive_file_outlined;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: C.slate100, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: C.fg2)),
      title: Text(str(f['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text([if (str(f['cat']).isNotEmpty) str(f['cat']), fmtDate(str(f['date']))].join(' · '), style: const TextStyle(fontSize: 12, color: C.fg3)),
      trailing: const Icon(Icons.open_in_new, size: 18, color: C.primary),
      onTap: () => openStoredFile(context, f),
    );
  }
}

class KV extends StatelessWidget {
  final String k, v;
  const KV(this.k, this.v, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: C.fg3, fontSize: 13))),
          Expanded(child: Text(v.isEmpty ? '—' : v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
        ]),
      );
}

class IssuesBox extends StatelessWidget {
  final List<String> issues;
  const IssuesBox(this.issues, {super.key});
  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.success50, borderRadius: BorderRadius.circular(14)),
        child: const Row(children: [Icon(Icons.check_circle, color: C.success), SizedBox(width: 8), Text('البيانات مكتملة', style: TextStyle(fontWeight: FontWeight.w700, color: C.success800))]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: C.warning50, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFED7AA))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.error_outline, color: C.warning), const SizedBox(width: 8), Expanded(child: Text('ملاحظات البيانات الناقصة', style: const TextStyle(fontWeight: FontWeight.w800))), Pill('${issues.length} ملاحظة', tone: Tone.orange)]),
        const SizedBox(height: 8),
        for (final i in issues) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.chevron_left, size: 18, color: C.warning), Expanded(child: Text(i, style: const TextStyle(fontSize: 13.5, color: C.fg2)))])),
      ]),
    );
  }
}

void toast(BuildContext context, String msg, {bool bad = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: bad ? C.danger : C.success800));
}

/// Search field used at the top of list screens.
class SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const SearchField(this.hint, {super.key, required this.onChanged});
  @override
  Widget build(BuildContext context) => TextField(decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search)), onChanged: onChanged);
}

/// Horizontal filter chips.
class FilterChips extends StatelessWidget {
  final List<(String, String)> items;
  final String value;
  final ValueChanged<String> onChanged;
  const FilterChips({super.key, required this.items, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (k, l) in items)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(l),
                selected: value == k,
                onSelected: (_) => onChanged(k),
                selectedColor: C.primary50,
                labelStyle: TextStyle(color: value == k ? C.primary700 : C.fg2, fontWeight: FontWeight.w600),
                side: BorderSide(color: value == k ? C.primary100 : C.slate200),
                showCheckmark: false,
              ),
            ),
        ]),
      );
}

/// Small icon + one-line text that ellipsizes instead of overflowing (safe inside Wrap/Row).
class IconText extends StatelessWidget {
  final IconData icon;
  final String text;
  const IconText(this.icon, this.text, {super.key});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: C.slate400),
        const SizedBox(width: 4),
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: C.fg2))),
      ]);
}
