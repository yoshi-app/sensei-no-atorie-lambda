const Redis = require('ioredis'); //パッケージioredisからRedisを取り出す
const redis = new Redis(process.env.REDIS_URL || 'redis://localhost:6379'); //RedisにRedisサーバーへの接続を作りredisインスタンスを作成する
const {Pool} = require('pg'); //パッケージpgからPoolだけを取り出す
const pool = new Pool({connectionString:process.env.DATABASE_URL}); //PoolにRDSサーバーへの接続を作りpoolインスタンスを作成する

const RATE_LIMIT = 5;
const GEMINI_MODEL = 'gemini-2.5-flash'
const GEMINI_ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

exports.handler = async(event) => {
    // リクエストを取り出す
    const body = JSON.parse(event.body || '{}') //ユーザーリクエスト（event.body）をオブジェクト形式に変換
    const {prompt, userId} = body ; //bodyからprompt,userIdを取り出す

    if(!prompt) { //promptが空のとき実行
        return  {statusCode:400, body:JSON.stringify({error:'prompt is required'})}; //stasuscode400（不正リクエスト）と「prompt is required」という文字列をエラーとして表示する
    }
    // レート制限チェック
    const today = new Date().toISOString().slice(0, 10); //現在の時刻の先頭から10文字を文字列として取り出す
    const key = `rl:${userId || 'anonymous'}:${today}` //userId,日付をユーザー識別キーとする

    try {
        const count = await redis.incr(key); //keyを引数としてredisカウンターを1増加させる、非同期処理で実行する
        if(count === 1) await redis.expire(key, 86400); //countが1のときredisカウンターのリセットタイマーを非同期実行する、24時間後keyを削除
        
        if(count >  RATE_LIMIT){ //countがRATE_LIMITを超過したとき
            return{
                statusCode:429,
                body:JSON.stringify({error:`1日の生成上限(${RATE_LIMIT}回)に達しました。明日またお試しください。`})
            }; //429（リクエスト回数超過）,1日の使用制限到達通知を文字列でユーザーに返す
        }
    } catch(kverr) { //kverr（try失敗）のとき
        console.error('KV error:',kverr); //エラー内容を「KV error:（エラー内容）」としてログに表示する
    }
    // Gemini呼び出し
    try {
        const geminiRes = await //HTTPにリクエストを送る、非同期実行
        fetch(`${GEMINI_ENDPOINT}?key=${process.env.GEMINI_API_KEY}`, { //Gemini（GeminiURL+GeminiAPIキー）に送る
            method: 'POST', //HTTPメソッドの指定：データ送信
            headers: {'Content-Type': 'application/json'}, //メタ情報：データのタイプapplication/json
            body: JSON.stringify({ //内容、以下を文字列とする
              contents: [{parts: [{text: prompt}] }], //内容：テキストのprompt
              generationConfig: {responseMimeType: 'application/json'} //レスポンスの指定：レスポンスデータ形式はapplicarion/json
            })
        });
    

    const data = await geminiRes.json() //geminiRes.json()非同期実行結果をdataとする
    // RDS保存
    try {
        await pool.query( //RDSサーバーにSQL文を送り、処理を実行する
           'INSERT INTO generations (user_id, prompt , result , created_at) VALUES($1, $2, $3, NOW())',
           [userId || 'anonymous', prompt, JSON.stringify(data)] 
        ); //テーブル名generationsに4つの列名を追加し、そこに４つの値を保存する　userIdがなければanonymousを返す　resultにはdataを文字列にしたもの
    } catch(dbErr)  { //dbErr（try失敗）のとき
        console.error('DB error:',dbErr); //エラーの内容を「DB error:(エラー内容)」としてログに表示する
    }
    //レスポンスを返す
    return { //ユーザーに返す
        statusCode: geminiRes.status, //geminiResの実行結果
        body: JSON.stringify(data) //実行結果の内容を文字列で表示
    };

    } catch(err) { //gemini呼び出しに失敗したとき
        console.error('Gemini error:', err); //エラーの内容を「Gemini error:（エラー内容）」としてログに表示する
        return{ //ユーザーに返す
            statusCode:500, //500（サーバーエラー）
            body: JSON.stringify({error: '生成に失敗しました。しばらく経ってから再試行してください'})
        }; //文字列で「error: (生成に〜)」を表示
    }
};