#!/bin/bash
set -e #エラーが発生したらスクリプトを停止する

AWS="aws --profile localstack --endpoint-url=http://localhost:4566"

#zipファイル作成
zip -r function.zip handler.js node_modules package.json
#ディレクトリごと（-r）３つのファイル・ディレクトリをfunction.zipファイルに圧縮

#Lambda関数作成
$AWS lambda create-function --function-name sensei-handler --runtime nodejs18.x --role arn:aws:iam::000000000000:role/sensei-lambda-role --handler handler.handler --zip-file fileb://function.zip
echo "Lambda関数作成成功"
#Lamda関数作成、実行環境Node.js　IAMロールARN handler.jsのhandler関数をhandlerに設定する　function.zipを展開する

#環境変数設定
$AWS lambda update-function-configuration --function-name sensei-handler --environment "Variables={GEMINI_API_KEY=${GEMINI_API_KEY},REDIS_URL=redis://localhost.localstack.cloud:4511,DATABASE_URL=postgresql://admin:password@localhost.localstack.cloud:4510/postgres}"
echo "環境変数設定完了"
#Lambda関数の設定　環境変数の設定（GeminiAPIキー、RedisURL、DatabaseURL）

#動作確認
$AWS lambda invoke --function-name sensei-handler --cli-binary-format raw-in-base64-out --payload file://payload.json response.json && cat response.json
echo "動作確認完了"
#Lambda関数を呼び出す　AWS CLIバイナリデータの扱い：文字列　prompt ser_idをデータとして送る　レスポンスはresponse.jsonとして保存する　response.jsonの中身を表示する