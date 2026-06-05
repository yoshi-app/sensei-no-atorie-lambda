#!/bin/bash
set -e #エラーが発生したらスクリプトを停止する

REGION="ap-northeast-1"
ACCOUNT_ID="000000000000" 

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

#REST API作成
REST_API_ID=$($AWS apigateway create-rest-api --name "sensei-api"  --query 'id' --output text)
echo "REST API ID: ${REST_API_ID}" 
#REST APIを作成してIDを格納する

#ルートリソースID取得
ROOT_RESOURCE_ID=$($AWS apigateway get-resources --rest-api-id $REST_API_ID --query 'items[0].id' --output text) 
echo "Root Resource ID: ${ROOT_RESOURCE_ID}"
#作成したREST APIからROOT API IDを取り出し格納する

#/generateリソース作成
RESOURCE_ID=$($AWS apigateway create-resource --rest-api-id $REST_API_ID --parent-id $ROOT_RESOURCE_ID --path-part "generate" --query 'id' --output text)
echo "Resource ID (/generate): ${RESOURCE_ID}"
#/generateリソースを作成しIDを格納する

#POSTメソッド設定
$AWS apigateway put-method --rest-api-id $REST_API_ID --resource-id $RESOURCE_ID --http-method POST --authorization-type NONE
echo "POSTメソッド設定完了"
#認証なし（NONE）でPOSTメソッドを設定する

#Lambda Proxyインテグレーション
$AWS apigateway put-integration --rest-api-id $REST_API_ID --resource-id $RESOURCE_ID --http-method POST --type AWS_PROXY --integration-http-method POST --uri arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:sensei-handler/invocations
echo "Lambda Proxyインテグレーション設定完了"
#リクエストを加工せずLambdaに渡す（AWS_PROXY） リソース識別（uri）＝API Gatewayリージョン＋Lambda関数のARN＋invoke（呼び出しのアクション）

#ステージdevにデプロイ
$AWS apigateway create-deployment --rest-api-id $REST_API_ID --stage-name "dev"
echo "ステージdevにデプロイ完了" 

#Lambda実行権限付与
$AWS lambda add-permission --function-name sensei-handler --statement-id "apigateway-invoke" --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${REST_API_ID}/*/POST/generate
echo "Lambda実行権限付与完了"
#許可アクション（action）：Lamda呼び出し　許可対象（principal）:API Gateway　どのAPI Gatewayか＝API Gareway ARN+リージョン＋アカウントID＋REST API ID＋＊（全てのステージ）＋POST（データ処理）＋リソース