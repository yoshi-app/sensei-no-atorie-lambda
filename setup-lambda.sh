#!/bin/bash
set -e

# エイリアス設定（~/.bashrcに追記済み・初回のみ実行）
# echo "alias awslocal='aws --profile localstack --endpoint-url=http://localhost:4566'" >> ~/.bashrc && source ~/.bashrc

AWS="aws --profile localstack --endpoint-url=http://localhost:4566"

VPC_ID=$($AWS ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
echo "VPC作成完了: $VPC_ID"

SUBNET_PUBLIC_ID=$($AWS ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.1.0/24 \
  --availability-zone ap-northeast-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=sensei-public-subnet}]' \
  --query 'Subnet.SubnetId' --output text)
echo "パブリックサブネット作成完了: $SUBNET_PUBLIC_ID"

SUBNET_PRIVATE_ID=$($AWS ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.2.0/24 \
  --availability-zone ap-northeast-1c \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=sensei-private-subnet}]' \
  --query 'Subnet.SubnetId' --output text)
echo "プライベートサブネット作成完了: $SUBNET_PRIVATE_ID"

LAMBDA_SG_ID=$($AWS ec2 create-security-group \                 
  --group-name sensei-lambda-sg \                            
  --description "Security group for Lambda" \                   
  --vpc-id "$VPC_ID" \                                       
  --query 'GroupId' --output text)                              
echo "Lambda用SG作成完了: $LAMBDA_SG_ID" 

RDS_SG_ID=$($AWS ec2 create-security-group \                 
  --group-name sensei-rds-sg \                                  
  --description "Security group for RDS" \
  --vpc-id "$VPC_ID" \                                          
  --query 'GroupId' --output text)                           
echo "RDS用SG作成完了: $RDS_SG_ID"

$AWS ec2 authorize-security-group-ingress \ 
  --group-id "$RDS_SG_ID" \                                     
  --protocol tcp \                                           
  --port 5432 \                                                 
  --source-group "$LAMBDA_SG_ID"
echo "RDS用SGインバウンドルール追加完了"

ROLE_ARN=$($AWS iam create-role --role-name sensei-lambda-role --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' --query 'Role.Arn' --output text)                                                           
echo "IAMロール作成完了: $ROLE_ARN"

$AWS elasticache create-cache-cluster --cache-cluster-id sensei-cache --engine redis --cache-node-type cache.t3.micro --num-cache-nodes 1
echo "Redisクラスター作成完了"

REDIS_HOST=$($AWS elasticache describe-cache-clusters --cache-cluster-id sensei-cache --show-cache-node-info --query "CacheClusters[0].CacheNodes[0].Endpoint.Address" --output text)
REDIS_PORT=$($AWS elasticache describe-cache-clusters --cache-cluster-id sensei-cache --show-cache-node-info --query "CacheClusters[0].CacheNodes[0].Endpoint.Port" --output text)
REDIS_ENDPOINT="${REDIS_HOST}:${REDIS_PORT}"
echo "Redisエンドポイント取得完了: $REDIS_ENDPOINT"

$AWS rds create-db-subnet-group  --db-subnet-group-name sensei-db-subnet-group  --db-subnet-group-description "Subnet group for RDS"  --subnet-ids "$SUBNET_PUBLIC_ID" "$SUBNET_PRIVATE_ID" 
echo "DBサブネットグループ作成完了"

RDS_ENDPOINT=$($AWS rds create-db-instance --db-instance-identifier sensei-db --db-instance-class db.t3.micro --engine postgres --master-username admin --master-user-password password --allocated-storage 20 --vpc-security-group-ids "$RDS_SG_ID" --db-subnet-group-name sensei-db-subnet-group --query 'DBInstance.Endpoint.Address' --output text)
echo "RDS作成完了: $RDS_ENDPOINT"

# IGW_ID=$($AWS ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
# echo "IGW作成完了: $IGW_ID"
# 
# $AWS ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
# echo "IGWアタッチ完了"
# 
# RTB_ID=$($AWS ec2 describe-route-tables \
#   --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" \
#   --query 'RouteTables[0].RouteTableId' --output text)
# echo "ルートテーブル取得完了: $RTB_ID"
# 
# $AWS ec2 create-route --route-table-id "$RTB_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID"
# echo "IGWへの経路追加完了"
# 
# $AWS ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET_PUBLIC_ID"
# echo "ルートテーブル関連付け完了"
# 
# $AWS ec2 modify-subnet-attribute --subnet-id "$SUBNET_PUBLIC_ID" --map-public-ip-on-launch
# echo "パブリックIP自動割り当て設定完了"
# 
# EC2_SG_ID=$($AWS ec2 create-security-group \
#   --group-name sensei-ec2-sg \
#   --description "Security group for EC2" \
#   --vpc-id "$VPC_ID" \
#   --query 'GroupId' --output text)
# echo "EC2用SG作成完了: $EC2_SG_ID"
# 
# $AWS ec2 authorize-security-group-ingress --group-id "$EC2_SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0
# echo "EC2用SGインバウンドルール追加完了（SSH）"
# 
# $AWS ec2 authorize-security-group-ingress --group-id "$EC2_SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0
# echo "EC2用SGインバウンドルール追加完了（HTTP）"
# 
# rm -f ~/sensei-no-atorie-key.pem
# $AWS ec2 create-key-pair --key-name sensei-no-atorie-key --query "KeyMaterial" --output text > ~/sensei-no-atorie-key.pem
# chmod 400 ~/sensei-no-atorie-key.pem
# echo "KeyPair作成完了"
# 
# INSTANCE_ID=$($AWS ec2 run-instances \
#   --image-id ami-04681a1dbd79675a5 \
#   --instance-type t2.micro \
#   --key-name sensei-no-atorie-key \
#   --subnet-id "$SUBNET_PUBLIC_ID" \
#   --security-group-ids "$EC2_SG_ID" \
#   --count 1 \
#   --query 'Instances[0].InstanceId' --output text)
# echo "EC2インスタンス起動完了: $INSTANCE_ID"
# 
# $AWS rds create-db-subnet-group --db-subnet-group-name sensei-db-subnet-group --db-subnet-group-description "Subnet group for RDS" --subnet-ids "$SUBNET_PUBLIC_ID" "$SUBNET_PRIVATE_ID" 
# echo "DBサブネットグループ作成完了"
# 
# RDS_ENDPOINT=$($AWS rds create-db-instance --db-instance-identifier sensei-db --db-instance-class db.t3.micro --engine postgres --master-username admin --master-user-password password --allocated-storage 20 --vpc-security-group-ids "$RDS_SG_ID" --db-subnet-group-name sensei-db-subnet-group --query 'DBInstance.Endpoint.Address' --output text)
# echo "RDS作成完了:$RDS_ENDPOINT"          
# 
# 
echo ""
echo "VPC_ID:            $VPC_ID"
echo "SUBNET_PUBLIC_ID:  $SUBNET_PUBLIC_ID"
echo "SUBNET_PRIVATE_ID: $SUBNET_PRIVATE_ID"
echo "LAMBDA_SG_ID:      $LAMBDA_SG_ID"
echo "RDS_SG_ID:         $RDS_SG_ID"
echo "ROLE_ARN:          $ROLE_ARN"
echo "REDIS_ENDPOINT:    $REDIS_ENDPOINT" 
echo "RDS_ENDPOINT:      $RDS_ENDPOINT" 
# echo "INSTANCE_ID:       $INSTANCE_ID"
# 
