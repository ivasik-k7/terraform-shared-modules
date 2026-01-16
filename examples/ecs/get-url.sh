#!/bin/bash

CLUSTER_NAME="archon-hub-dev-cluster"
REGION="us-east-1"
SERVICES=("nginx" "httpd" "caddy")

echo "🔍 Finding running tasks for all services..."
echo ""

for SERVICE_NAME in "${SERVICES[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Service: $SERVICE_NAME"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    TASK_ARN=$(aws ecs list-tasks --region "$REGION" --cluster "$CLUSTER_NAME" --service-name "$SERVICE_NAME" --desired-status RUNNING --query 'taskArns[0]' --output text 2>/dev/null)

    if [ "$TASK_ARN" == "None" ] || [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "null" ]; then
        echo "⏳ Task is starting or not found yet..."
        echo "   Run this script again in a few seconds"
        echo ""
        continue
    fi

    ENI_ID=$(aws ecs describe-tasks --region "$REGION" --cluster "$CLUSTER_NAME" --tasks "$TASK_ARN" --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text 2>/dev/null)

    if [ -z "$ENI_ID" ] || [ "$ENI_ID" == "None" ]; then
        echo "⏳ Network interface not ready yet..."
        echo "   Run this script again in a few seconds"
        echo ""
        continue
    fi

    PUBLIC_IP=$(aws ec2 describe-network-interfaces --region "$REGION" --network-interface-ids "$ENI_ID" --query 'NetworkInterfaces[0].Association.PublicIp' --output text 2>/dev/null)

    if [ "$PUBLIC_IP" == "None" ] || [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" == "null" ]; then
        echo "⏳ Public IP not assigned yet..."
        echo "   Run this script again in a few seconds"
        echo ""
        continue
    fi

    echo "✅ Running!"
    echo "🌍 URL: http://$PUBLIC_IP"
    echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 Open the URLs above in your browser"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
