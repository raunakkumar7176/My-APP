import fs from 'fs';
import path from 'path';
import { Client } from 'pg';

interface TranslationPair {
  name?: string;
  title?: string;
  description?: string;
  summary?: string;
}

interface BlockContent {
  text?: string;
  latex?: string;
  points?: string[];
  [key: string]: unknown;
}

interface ContentBlockItem {
  order_index: number;
  block_type: string;
  content: {
    en: BlockContent;
    hi: BlockContent;
  };
}

interface TopicItem {
  topic_key: string;
  order_index: number;
  estimated_minutes?: number;
  translations: {
    en: { title: string; summary?: string };
    hi: { title: string; summary?: string };
  };
  content_blocks: ContentBlockItem[];
}

interface QuestionTranslation {
  question: string;
  options: string[];
  explanation: string;
}

interface QuestionItem {
  topic_key: string;
  difficulty: 'easy' | 'medium' | 'hard';
  correct_option: number;
  translations: {
    en: QuestionTranslation;
    hi: QuestionTranslation;
  };
}

interface SeedData {
  subject_key: string;
  subject_slug?: string;
  subject_icon?: string;
  subject_order_index?: number;
  subject_translations: {
    en: { name: string; description?: string };
    hi: { name: string; description?: string };
  };
  part_key?: string;
  part_order_index?: number;
  part_translations?: {
    en: string;
    hi: string;
  };
  chapter_key: string;
  order_index?: number;
  version?: number;
  chapter_translations: {
    en: { title: string; description?: string };
    hi: { title: string; description?: string };
  };
  topics: TopicItem[];
  questions: QuestionItem[];
}

const VALID_BLOCK_TYPES = new Set([
  'heading',
  'paragraph',
  'definition',
  'formula',
  'example',
  'important_point',
  'note',
  'table',
  'image',
  'common_mistake',
]);

const VALID_DIFFICULTIES = new Set(['easy', 'medium', 'hard', 'basic', 'mixed']);

export function validateSeedData(data: unknown): SeedData {
  if (!data || typeof data !== 'object') {
    throw new Error('Seed data must be a non-null JSON object');
  }

  const d = data as Partial<SeedData>;

  if (!d.subject_key || typeof d.subject_key !== 'string') {
    throw new Error('Missing or invalid "subject_key"');
  }

  if (!d.subject_translations?.en?.name || !d.subject_translations?.hi?.name) {
    throw new Error('Missing subject_translations for either "en" or "hi"');
  }

  if (!d.chapter_key || typeof d.chapter_key !== 'string') {
    throw new Error('Missing or invalid "chapter_key"');
  }

  if (!d.chapter_translations?.en?.title || !d.chapter_translations?.hi?.title) {
    throw new Error('Missing chapter_translations for either "en" or "hi"');
  }

  if (d.part_key !== undefined && (typeof d.part_key !== 'string' || d.part_key.trim() === '')) {
    throw new Error('If provided, "part_key" must be a non-empty string');
  }

  if (d.part_translations !== undefined) {
    if (!d.part_translations?.en || !d.part_translations?.hi) {
      throw new Error('"part_translations" must contain both "en" and "hi" strings');
    }
  }

  if (!Array.isArray(d.topics) || d.topics.length === 0) {
    throw new Error('At least one topic must be defined in "topics"');
  }

  const topicKeys = new Set<string>();

  for (const [idx, t] of d.topics.entries()) {
    if (!t.topic_key || typeof t.topic_key !== 'string') {
      throw new Error(`Topic at index ${idx} missing "topic_key"`);
    }
    if (topicKeys.has(t.topic_key)) {
      throw new Error(`Duplicate topic_key detected: "${t.topic_key}"`);
    }
    topicKeys.add(t.topic_key);

    if (!t.translations?.en?.title || !t.translations?.hi?.title) {
      throw new Error(`Topic "${t.topic_key}" missing bilingual title (en/hi)`);
    }

    if (!Array.isArray(t.content_blocks) || t.content_blocks.length === 0) {
      throw new Error(`Topic "${t.topic_key}" has no content_blocks`);
    }

    for (const [bIdx, b] of t.content_blocks.entries()) {
      if (!VALID_BLOCK_TYPES.has(b.block_type)) {
        throw new Error(`Topic "${t.topic_key}" block ${bIdx} has invalid block_type "${b.block_type}"`);
      }
      if (!b.content?.en || !b.content?.hi) {
        throw new Error(`Topic "${t.topic_key}" block ${bIdx} missing "en" or "hi" content payload`);
      }
    }
  }

  if (Array.isArray(d.questions)) {
    for (const [qIdx, q] of d.questions.entries()) {
      if (!topicKeys.has(q.topic_key)) {
        throw new Error(`Question ${qIdx} references unknown topic_key "${q.topic_key}"`);
      }
      if (!VALID_DIFFICULTIES.has(q.difficulty)) {
        throw new Error(`Question ${qIdx} has invalid difficulty "${q.difficulty}"`);
      }
      if (typeof q.correct_option !== 'number' || q.correct_option < 0 || q.correct_option > 3) {
        throw new Error(`Question ${qIdx} correct_option must be an integer between 0 and 3`);
      }
      for (const lang of ['en', 'hi'] as const) {
        const trans = q.translations?.[lang];
        if (!trans || !trans.question) {
          throw new Error(`Question ${qIdx} missing question text for language "${lang}"`);
        }
        if (!Array.isArray(trans.options) || trans.options.length !== 4) {
          throw new Error(`Question ${qIdx} must have exactly 4 options for language "${lang}"`);
        }
      }
    }
  }

  return d as SeedData;
}

export async function importStudyContent(filePath: string): Promise<void> {
  console.log(`\n======================================================`);
  console.log(`[STUDY INGESTION] Reading: ${filePath}`);
  console.log(`======================================================`);

  const resolvedPath = path.resolve(filePath);
  if (!fs.existsSync(resolvedPath)) {
    throw new Error(`File not found: ${resolvedPath}`);
  }

  const rawJson = fs.readFileSync(resolvedPath, 'utf8');
  const data = validateSeedData(JSON.parse(rawJson));
  console.log(`[VALIDATION] JSON schema validated successfully.`);
  console.log(`  Subject: ${data.subject_key}`);
  console.log(`  Chapter: ${data.chapter_key}`);
  console.log(`  Topics: ${data.topics.length}`);
  console.log(`  Questions: ${data.questions.length}`);

  const client = new Client({
    host: process.env.SUPABASE_DB_HOST || 'aws-0-ap-northeast-1.pooler.supabase.com',
    port: Number(process.env.SUPABASE_DB_PORT || 6543),
    user: process.env.SUPABASE_DB_USER || 'postgres.cnwtprexxjrajcdjhfsr',
    password: process.env.SUPABASE_DB_PASSWORD || 'RRaunak@7176',
    database: process.env.SUPABASE_DB_NAME || 'postgres',
    ssl: { rejectUnauthorized: false },
    statement_timeout: 30000,
  });

  await client.connect();

  const metrics = {
    subjectsUpserted: 0,
    subjectTranslationsUpserted: 0,
    chaptersUpserted: 0,
    chapterTranslationsUpserted: 0,
    topicsUpserted: 0,
    topicTranslationsUpserted: 0,
    contentBlocksUpserted: 0,
    questionsInserted: 0,
    questionsUpdated: 0,
  };

  try {
    await client.query('BEGIN');

    // 1. Upsert Subject
    const enSubName = data.subject_translations.en.name;
    const subRes = await client.query(
      `INSERT INTO public.subjects (name, slug, icon, order_index, is_active, status, updated_at)
       VALUES ($1, $2, $3, $4, true, 'published', now())
       ON CONFLICT (name) DO UPDATE SET
         slug = EXCLUDED.slug,
         icon = COALESCE(EXCLUDED.icon, subjects.icon),
         order_index = EXCLUDED.order_index,
         status = 'published',
         is_active = true,
         updated_at = now()
       RETURNING id;`,
      [
        enSubName,
        data.subject_slug || data.subject_key,
        data.subject_icon || 'book',
        data.subject_order_index || 0,
      ]
    );
    const subjectId = subRes.rows[0].id as string;
    metrics.subjectsUpserted++;

    // 1b. Upsert Subject Translations
    for (const lang of ['en', 'hi'] as const) {
      const trans = data.subject_translations[lang];
      await client.query(
        `INSERT INTO public.subject_translations (subject_id, language, name, description, updated_at)
         VALUES ($1, $2, $3, $4, now())
         ON CONFLICT (subject_id, language) DO UPDATE SET
           name = EXCLUDED.name,
           description = EXCLUDED.description,
           updated_at = now();`,
        [subjectId, lang, trans.name, trans.description || '']
      );
      metrics.subjectTranslationsUpserted++;
    }

    // 2. Upsert Chapter
    const chapRes = await client.query(
      `INSERT INTO public.chapters (
         subject_id, chapter_key, part_key, part_order_index, order_index, is_active, status, version, updated_at
       )
       VALUES ($1, $2, $3, $4, $5, true, 'published', $6, now())
       ON CONFLICT (subject_id, chapter_key) DO UPDATE SET
         part_key = EXCLUDED.part_key,
         part_order_index = EXCLUDED.part_order_index,
         order_index = EXCLUDED.order_index,
         status = 'published',
         is_active = true,
         version = EXCLUDED.version,
         updated_at = now()
       RETURNING id;`,
      [
        subjectId,
        data.chapter_key,
        data.part_key || null,
        data.part_order_index || 0,
        data.order_index || 0,
        data.version || 1,
      ]
    );
    const chapterId = chapRes.rows[0].id as string;
    metrics.chaptersUpserted++;

    // 2b. Upsert Chapter Translations
    for (const lang of ['en', 'hi'] as const) {
      const trans = data.chapter_translations[lang];
      const partTitle = data.part_translations?.[lang] || null;
      await client.query(
        `INSERT INTO public.chapter_translations (
           chapter_id, language, title, description, part_title, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, now())
         ON CONFLICT (chapter_id, language) DO UPDATE SET
           title = EXCLUDED.title,
           description = EXCLUDED.description,
           part_title = COALESCE(EXCLUDED.part_title, chapter_translations.part_title),
           updated_at = now();`,
        [chapterId, lang, trans.title, trans.description || '', partTitle]
      );
      metrics.chapterTranslationsUpserted++;
    }

    // 3. Upsert Topics and Content Blocks
    const topicIdMap = new Map<string, string>();

    for (const topic of data.topics) {
      const topRes = await client.query(
        `INSERT INTO public.topics (chapter_id, topic_key, order_index, is_active, status, estimated_minutes, updated_at)
         VALUES ($1, $2, $3, true, 'published', $4, now())
         ON CONFLICT (chapter_id, topic_key) DO UPDATE SET
           order_index = EXCLUDED.order_index,
           status = 'published',
           is_active = true,
           estimated_minutes = EXCLUDED.estimated_minutes,
           updated_at = now()
         RETURNING id;`,
        [chapterId, topic.topic_key, topic.order_index, topic.estimated_minutes || 5]
      );
      const topicId = topRes.rows[0].id as string;
      topicIdMap.set(topic.topic_key, topicId);
      metrics.topicsUpserted++;

      // 3b. Topic Translations
      for (const lang of ['en', 'hi'] as const) {
        const trans = topic.translations[lang];
        await client.query(
          `INSERT INTO public.topic_translations (topic_id, language, title, summary, updated_at)
           VALUES ($1, $2, $3, $4, now())
           ON CONFLICT (topic_id, language) DO UPDATE SET
             title = EXCLUDED.title,
             summary = EXCLUDED.summary,
             updated_at = now();`,
          [topicId, lang, trans.title, trans.summary || '']
        );
        metrics.topicTranslationsUpserted++;
      }

      // 3c. Content Blocks (Match on topic_id, language, order_index)
      for (const block of topic.content_blocks) {
        for (const lang of ['en', 'hi'] as const) {
          const payload = block.content[lang];
          await client.query(
            `INSERT INTO public.content_blocks (topic_id, block_type, language, order_index, content, is_active, status, updated_at)
             VALUES ($1, $2, $3, $4, $5::jsonb, true, 'published', now())
             ON CONFLICT (topic_id, language, order_index) DO UPDATE SET
               block_type = EXCLUDED.block_type,
               content = EXCLUDED.content,
               is_active = true,
               status = 'published',
               updated_at = now();`,
            [topicId, block.block_type, lang, block.order_index, JSON.stringify(payload)]
          );
          metrics.contentBlocksUpserted++;
        }
      }
    }

    // 4. Upsert Questions into question_bank
    const chapterName = data.chapter_translations.en.title;

    for (const q of data.questions) {
      const topicId = topicIdMap.get(q.topic_key);

      for (const lang of ['en', 'hi'] as const) {
        const qTrans = q.translations[lang];
        const questionText = qTrans.question.trim();
        const optionsJson = JSON.stringify(
          qTrans.options.map((opt, i) => ({ id: `opt_${i + 1}`, text: opt }))
        );

        // Normalize duplicate key matching existing 0045 rule
        const dupKey = questionText.toLowerCase().replace(/\s+/g, ' ');

        // Check if question exists in question_bank
        const existing = await client.query(
          `SELECT id FROM public.question_bank
           WHERE (chapter_id = $1 OR chapter_id IS NULL)
             AND duplicate_key = $2
             AND language = $3
           LIMIT 1;`,
          [chapterId, dupKey, lang]
        );

        if (existing.rows.length > 0) {
          const qId = existing.rows[0].id;
          await client.query(
            `UPDATE public.question_bank
             SET options = $1::jsonb,
                 correct_option = $2,
                 explanation = $3,
                 subject_id = $4,
                 subject_name = $5,
                 chapter = $6,
                 chapter_id = $7,
                 topic_id = $8,
                 difficulty = $9,
                 status = 'approved',
                 source = 'manual',
                 updated_at = now()
             WHERE id = $10;`,
            [
              optionsJson,
              q.correct_option,
              qTrans.explanation,
              subjectId,
              enSubName,
              chapterName,
              chapterId,
              topicId,
              q.difficulty,
              qId,
            ]
          );
          metrics.questionsUpdated++;
        } else {
          await client.query(
            `INSERT INTO public.question_bank (
               question, options, correct_option, explanation,
               subject_id, subject_name, chapter, chapter_id, topic_id,
               difficulty, language, question_type, source, status,
               created_at, updated_at
             ) VALUES (
               $1, $2::jsonb, $3, $4,
               $5, $6, $7, $8, $9,
               $10, $11, 'mcq', 'manual', 'approved',
               now(), now()
             );`,
            [
              questionText,
              optionsJson,
              q.correct_option,
              qTrans.explanation,
              subjectId,
              enSubName,
              chapterName,
              chapterId,
              topicId,
              q.difficulty,
              lang,
            ]
          );
          metrics.questionsInserted++;
        }
      }
    }

    await client.query('COMMIT');
    console.log(`[SUCCESS] Database transaction committed successfully.`);
    console.table(metrics);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error(`[ERROR] Ingestion failed. Transaction rolled back.`);
    throw err;
  } finally {
    await client.end();
  }
}

// CLI Execution entry point
const targetFile = process.argv[2] || 'content/mathematics/number-system.json';
importStudyContent(targetFile).catch((err) => {
  console.error('\nFatal Error:', err);
  process.exit(1);
});

