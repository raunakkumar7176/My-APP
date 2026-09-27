import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/content_block.dart';

/// Renders a single [ContentBlock] based on its [ContentBlockType].
///
/// Designed to provide high-clarity textbook typography, visual cues, and
/// distinct callouts for mathematical formulas, conceptual definitions,
/// teacher tips, and common exam pitfalls.
class ContentBlockRenderer extends StatelessWidget {
  const ContentBlockRenderer({
    super.key,
    required this.block,
    this.isHindi = false,
    this.margin = const EdgeInsets.only(bottom: 18.0),
    this.fontScale = 1.0,
  });

  final ContentBlock block;
  final bool isHindi;
  final EdgeInsetsGeometry? margin;

  /// Multiplies the body-text font sizes (not badge/label captions), driven
  /// by the reader's A-/A+ stepper. 1.0 = the original fixed sizes below.
  final double fontScale;

  /// Scales a body-text size; labels/badges/icons stay fixed for legibility.
  double _f(double base) => base * fontScale;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final child = switch (block.blockType) {
      ContentBlockType.heading => _buildHeading(context, isDark),
      ContentBlockType.paragraph => _buildParagraph(context, isDark),
      ContentBlockType.definition => _buildDefinition(context, isDark),
      ContentBlockType.formula => _buildFormula(context, isDark),
      ContentBlockType.example => _buildExample(context, isDark),
      ContentBlockType.importantPoint => _buildImportantPoint(context, isDark),
      ContentBlockType.commonMistake => _buildCommonMistake(context, isDark),
      ContentBlockType.note => _buildNote(context, isDark),
      ContentBlockType.table => _buildTable(context, isDark),
      ContentBlockType.image => _buildImage(context, isDark),
      ContentBlockType.unknown => _buildParagraph(context, isDark),
    };

    if (margin != null) {
      return Padding(padding: margin!, child: child);
    }
    return child;
  }

  // ── 1. Heading ─────────────────────────────────────────────────────────────
  Widget _buildHeading(BuildContext context, bool isDark) {
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final accentColor = isDark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF2563EB);

    return Padding(
      padding: const EdgeInsets.only(top: 20.0, bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 24,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Text(
              block.text,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: _f(20),
                fontWeight: FontWeight.w700,
                color: textColor,
                letterSpacing: -0.3,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. Paragraph ───────────────────────────────────────────────────────────
  Widget _buildParagraph(BuildContext context, bool isDark) {
    final textColor = isDark
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF334155);

    return Text(
      block.text,
      style: TextStyle(
        fontFamily: 'Roboto',
        fontSize: _f(15.5),
        fontWeight: FontWeight.w400,
        height: 1.65,
        letterSpacing: 0.1,
        color: textColor,
      ),
    );
  }

  // ── 3. Definition ──────────────────────────────────────────────────────────
  Widget _buildDefinition(BuildContext context, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final accentColor = isDark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF2563EB);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 8),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left colored accent bar
            Container(width: 4.5, color: accentColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withAlpha(isDark ? 45 : 30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bookmark_rounded,
                                size: 13,
                                color: accentColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isHindi ? 'परिभाषा' : 'DEFINITION',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  color: accentColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      block.text,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: _f(15),
                        fontWeight: FontWeight.w500,
                        height: 1.6,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 4. Formula ─────────────────────────────────────────────────────────────
  Widget _buildFormula(BuildContext context, bool isDark) {
    final mathFormula = block.latex ?? block.text;
    final primaryAccent = isDark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF2563EB);
    final cardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final containerBg = isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF1F5F9);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 8),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (block.text.isNotEmpty && block.latex != null) ...[
            Text(
              block.text,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: containerBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(Icons.functions_rounded, size: 20, color: primaryAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      mathFormula,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: _f(15),
                        fontWeight: FontWeight.w600,
                        color: primaryAccent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  tooltip: isHindi ? 'फॉर्मूला कॉपी करें' : 'Copy formula',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: mathFormula));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isHindi
                              ? 'फॉर्मूला क्लिपबोर्ड पर कॉपी हो गया'
                              : 'Formula copied to clipboard',
                        ),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 5. Example ─────────────────────────────────────────────────────────────
  Widget _buildExample(BuildContext context, bool isDark) {
    final accentColor = isDark
        ? const Color(0xFF38BDF8)
        : const Color(0xFF0284C7);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final dividerColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFF1F5F9);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    final problemText =
        (block.content['problem'] as String?) ??
        (block.content['question'] as String?) ??
        block.text;
    final solutionText =
        (block.content['solution'] as String?) ??
        (block.content['answer'] as String?) ??
        block.latex;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 8),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withAlpha(isDark ? 40 : 25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lightbulb_rounded,
                        size: 13,
                        color: accentColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isHindi ? 'उदाहरण' : 'WORKED EXAMPLE',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: dividerColor),

          // Problem Row
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isHindi ? 'प्रश्न / समस्या:' : 'Problem:',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  problemText,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: _f(14.5),
                    fontWeight: FontWeight.w500,
                    height: 1.55,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),

          // Solution Row (Separated by clear soft border)
          if (solutionText != null && solutionText.trim().isNotEmpty) ...[
            Divider(height: 1, thickness: 1, color: dividerColor),
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A).withAlpha(120)
                    : const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 14,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isHindi ? 'हल / व्याख्या:' : 'Solution & Explanation:',
                        style: const TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    solutionText,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: _f(14),
                      fontWeight: FontWeight.w400,
                      height: 1.6,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 6. Important Point ─────────────────────────────────────────────────────
  Widget _buildImportantPoint(BuildContext context, bool isDark) {
    const accentColor = Color(0xFFD97706); // Amber 600
    final cardBg = isDark ? const Color(0xFF231C10) : const Color(0xFFFFFBEB);
    final borderColor = isDark
        ? const Color(0xFF5B3908)
        : const Color(0xFFFDE68A);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 8),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, size: 16, color: accentColor),
              const SizedBox(width: 6),
              Text(
                isHindi ? 'महत्वपूर्ण बिंदु' : 'IMPORTANT TO REMEMBER',
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (block.text.isNotEmpty) ...[
            Text(
              block.text,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: _f(14.5),
                fontWeight: FontWeight.w600,
                height: 1.5,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (block.points.isNotEmpty)
            ...block.points.map((pt) {
              return Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 7.0, right: 8.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accentColor,
                        ),
                        child: SizedBox(width: 5, height: 5),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        pt,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: _f(14),
                          height: 1.55,
                          color: textColor,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ── 7. Common Mistake ──────────────────────────────────────────────────────
  Widget _buildCommonMistake(BuildContext context, bool isDark) {
    const errorColor = Color(0xFFDC2626);
    const successColor = Color(0xFF16A34A);
    final cardBg = isDark ? const Color(0xFF2D1616) : const Color(0xFFFEF2F2);
    final borderColor = isDark
        ? const Color(0xFF5B1E1E)
        : const Color(0xFFFECACA);

    final mistake = block.content['mistake']?.toString();
    final correction = block.content['correction']?.toString();

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 8),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: errorColor,
              ),
              const SizedBox(width: 6),
              Text(
                isHindi ? 'सामान्य गलती (सावधान)' : 'COMMON PITFALL / MISTAKE',
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: errorColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (mistake != null && mistake.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: errorColor.withAlpha(isDark ? 40 : 15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.close_rounded, size: 16, color: errorColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${isHindi ? "गलती" : "Mistake"}: $mistake',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: _f(13.5),
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                        color: isDark ? const Color(0xFFFCA5A5) : errorColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (correction != null && correction.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: successColor.withAlpha(isDark ? 40 : 15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: successColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${isHindi ? "सही समझ" : "Correct Understanding"}: $correction',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: _f(13.5),
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                          color: isDark
                              ? const Color(0xFF86EFAC)
                              : successColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ] else ...[
            Text(
              block.text,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: _f(14),
                fontWeight: FontWeight.w400,
                height: 1.5,
                color: isDark
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFF7F1D1D),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 8. Note ────────────────────────────────────────────────────────────────
  Widget _buildNote(BuildContext context, bool isDark) {
    final noteColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final cardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: noteColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              block.text,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: _f(14),
                fontStyle: FontStyle.italic,
                height: 1.55,
                color: noteColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 9. Image ───────────────────────────────────────────────────────────────
  Widget _buildImage(BuildContext context, bool isDark) {
    final url = block.mediaUrl;
    if (url == null || url.isEmpty) {
      return const SizedBox.shrink();
    }

    final cardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            cacheWidth:
                (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context))
                    .round(),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                height: 180,
                color: cardBg,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: 130,
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.broken_image_rounded,
                        size: 32,
                        color: textSecondary,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isHindi
                            ? 'चित्र लोड करने में असमर्थ'
                            : 'Failed to load illustration',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (block.text.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            block.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              color: textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  // ── 10. Table ──────────────────────────────────────────────────────────────
  Widget _buildTable(BuildContext context, bool isDark) {
    final headers = block.content['headers'];
    final rows = block.content['rows'];
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final headerBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

    if (headers is List && rows is List) {
      final headerCols = headers
          .map(
            (h) => DataColumn(
              label: Text(
                h.toString(),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          )
          .toList();
      final tableRows = rows.map((r) {
        if (r is List) {
          return DataRow(
            cells: r
                .map(
                  (c) => DataCell(
                    Text(c.toString(), style: const TextStyle(fontSize: 13)),
                  ),
                )
                .toList(),
          );
        }
        return const DataRow(cells: []);
      }).toList();

      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(headerBg),
            columns: headerCols,
            rows: tableRows,
            border: TableBorder(
              horizontalInside: BorderSide(color: borderColor),
            ),
          ),
        ),
      );
    }

    return _buildParagraph(context, isDark);
  }
}
