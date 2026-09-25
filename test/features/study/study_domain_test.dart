import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/study/study.dart';

void main() {
  group('Study Domain Models - Translation Fallback Tests', () {
    test('StudySubject falls back gracefully to English when Hindi translation is absent', () {
      final subjectMap = {
        'id': 'sub-1',
        'subject_key': 'mathematics',
        'icon': 'calculator',
        'order_index': 1,
        'subject_translations': [
          {
            'language': 'en',
            'name': 'Mathematics',
            'description': 'Master core mathematical concepts and formulas.',
          },
        ],
      };

      // Request Hindi when only English is present
      final subjectHi = StudySubject.fromMap(subjectMap, languageCode: 'hi');
      expect(subjectHi.name, 'Mathematics');
      expect(
        subjectHi.description,
        'Master core mathematical concepts and formulas.',
      );

      // Request English
      final subjectEn = StudySubject.fromMap(subjectMap, languageCode: 'en');
      expect(subjectEn.name, 'Mathematics');
    });

    test(
      'StudyChapter falls back to English when Hindi translation is absent',
      () {
        final chapterMap = {
          'id': 'chap-1',
          'subject_id': 'sub-1',
          'chapter_key': 'number_system',
          'order_index': 1,
          'chapter_translations': [
            {
              'language': 'en',
              'title': 'Number System',
              'description': 'Foundational properties of numbers.',
            },
          ],
        };

        // Request Hindi when only English is present
        final chapterHi = StudyChapter.fromMap(chapterMap, languageCode: 'hi');
        expect(chapterHi.title, 'Number System');
        expect(chapterHi.description, 'Foundational properties of numbers.');
        expect(chapterHi.partKey, isNull);
        expect(chapterHi.partTitle, isNull);
        expect(chapterHi.partOrderIndex, 0);
      },
    );

    test('StudyChapter parses part_key, part_title, and part_order_index correctly', () {
      final multiPartChapterMap = {
        'id': 'chap-2',
        'subject_id': 'sub-hist',
        'chapter_key': 'indus_valley_civilization',
        'part_key': 'ancient_history',
        'part_order_index': 1,
        'order_index': 1,
        'chapter_translations': [
          {
            'language': 'en',
            'title': 'Indus Valley Civilization',
            'part_title': 'Ancient History',
          },
          {
            'language': 'hi',
            'title': 'सिंधु घाटी सभ्यता',
            'part_title': 'प्राचीन इतिहास',
          },
        ],
      };

      final chapterEn = StudyChapter.fromMap(
        multiPartChapterMap,
        languageCode: 'en',
      );
      expect(chapterEn.partKey, 'ancient_history');
      expect(chapterEn.partTitle, 'Ancient History');
      expect(chapterEn.partOrderIndex, 1);
      expect(chapterEn.title, 'Indus Valley Civilization');

      final chapterHi = StudyChapter.fromMap(
        multiPartChapterMap,
        languageCode: 'hi',
      );
      expect(chapterHi.partKey, 'ancient_history');
      expect(chapterHi.partTitle, 'प्राचीन इतिहास');
      expect(chapterHi.title, 'सिंधु घाटी सभ्यता');
    });

    test(
      'StudyTopic falls back to English when Hindi translation is absent',
      () {
        final topicMap = {
          'id': 'top-1',
          'chapter_id': 'chap-1',
          'topic_key': 'natural_numbers',
          'order_index': 1,
          'estimated_minutes': 7,
          'topic_translations': [
            {
              'language': 'en',
              'title': 'Natural Numbers',
              'summary': 'Counting numbers starting from 1.',
            },
          ],
        };

        // Request Hindi when only English is present
        final topicHi = StudyTopic.fromMap(topicMap, languageCode: 'hi');
        expect(topicHi.title, 'Natural Numbers');
        expect(topicHi.summary, 'Counting numbers starting from 1.');
        expect(topicHi.estimatedMinutes, 7);
      },
    );

    test(
      'StudyTopic falls back to topic_key if no translations exist at all',
      () {
        final topicMap = {
          'id': 'top-2',
          'chapter_id': 'chap-1',
          'topic_key': 'complex_numbers',
          'order_index': 2,
          'topic_translations': [],
        };

        final topic = StudyTopic.fromMap(topicMap, languageCode: 'hi');
        expect(topic.title, 'complex_numbers');
        expect(topic.summary, '');
      },
    );

    test('ContentBlock parses various block types safely', () {
      final blockMap = {
        'id': 'blk-1',
        'topic_id': 'top-1',
        'block_type': 'formula',
        'order_index': 1,
        'content': {
          'en': {'latex': r'\sum_{i=1}^n i = \frac{n(n+1)}{2}'},
          'hi': {'latex': r'\sum_{i=1}^n i = \frac{n(n+1)}{2}'},
        },
      };

      final block = ContentBlock.fromMap(blockMap);
      expect(block.blockType, ContentBlockType.formula);
      expect(
        block.content['en']['latex'],
        r'\sum_{i=1}^n i = \frac{n(n+1)}{2}',
      );
    });
  });
}
