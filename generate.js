const Redis  = require('ioredis');
const redis = new Redis(process.env.REDIS_URL || 'redis://localhost:6379');
const { Pool } = require('pg');
const pool = new Pool({ connectionString:
process.env.DATABASE_URL });

const RATE_LIMIT = 5;
const GEMINI_MODEL = 'gemini-2.5-flash';
const GEMINI_ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const { prompt } = req.body;
  if (!prompt) return res.status(400).json({ error: 'prompt is required' });

  // IPの取得
  const ip = (req.headers['x-forwarded-for'] || '').split(',')[0].trim() || 'unknown';
  const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD JST補正
  const key = `rl:${ip}:${today}`;

  // レート制限チェック
  try {
    const count = await redis.incr(key);
    if (count === 1) await redis.expire(key, 86400); // 24時間で自動削除

    if (count > RATE_LIMIT) {
      return res.status(429).json({
        error: `1日の生成上限（${RATE_LIMIT}回）に達しました。明日またお試しください。`
      });
    }
  } catch (kvErr) {
    console.error('KV error:', kvErr);
    // KV障害時はレート制限をスキップして続行
  }

  // Gemini API 呼び出し
  try {
    const geminiRes = await fetch(`${GEMINI_ENDPOINT}?key=${process.env.GEMINI_API_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { responseMimeType: 'application/json' }
      })
    });

    const data = await geminiRes.json();
    // RDSに保存
    try {
      await pool.query(
        'INSERT INTO generations (ip, prompt, result, created_at)  VALUES ($1, $2, $3, NOW())',
        [ip, prompt, JSON.stringify(data)]
      );
     } catch (dbErr) {
       console.error('DB error:', dbErr);
       // DB障害時もレスポンスは返す
     }

    return res.status(geminiRes.status).json(data);

  } catch (err) {
    console.error('Gemini error:', err);
    return res.status(500).json({ error: '生成に失敗しました。しばらく経ってから再試行してください。' });
  }
};
