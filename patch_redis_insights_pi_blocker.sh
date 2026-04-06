#!/bin/bash

# Script to patch RedisCluster resources with redis_insights_pi_blocker annotation
# Usage: ./patch_redis_insights_pi_blocker.sh <clusters_file> <true|false>
# clusters_file.txt: a file listing the clusters to modify in format namespace:cluster_name

set -e

CLUSTERS_FILE="${1:-clusters.txt}"
PI_BLOCKER_VALUE="${2:-true}"

if [ ! -f "$CLUSTERS_FILE" ]; then
    echo "Error: Clusters file '$CLUSTERS_FILE' not found!"
    echo "Usage: $0 <clusters_file> <true|false>"
    echo ""
    echo "Create a clusters file with format:"
    echo "  namespace:cluster-name"
    echo ""
    echo "Example:"
    echo "  sn-abtest:sn-abtest-redis-cluster"
    echo "  sn-gateway:sn-gateway-redis-cluster"
    exit 1
fi

if [[ "$PI_BLOCKER_VALUE" != "true" && "$PI_BLOCKER_VALUE" != "false" ]]; then
    echo "Error: PI blocker value must be 'true' or 'false'"
    echo "Usage: $0 <clusters_file> <true|false>"
    exit 1
fi

echo "========================================"
echo "Redis Insights PI Blocker Batch Patcher"
echo "========================================"
echo "Clusters file: $CLUSTERS_FILE"
echo "Setting value: $PI_BLOCKER_VALUE"
echo ""

# Count total clusters
total=$(grep -v '^#' "$CLUSTERS_FILE" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')
echo "Total clusters to patch: $total"
echo ""

# Patch each cluster
success=0
failed=0

while IFS=: read -r namespace name || [ -n "$namespace" ]; do
    # Skip empty lines and comments
    [[ -z "$namespace" || "$namespace" =~ ^[[:space:]]*# ]] && continue

    # Trim whitespace
    namespace=$(echo "$namespace" | xargs)
    name=$(echo "$name" | xargs)

    echo "----------------------------------------"
    echo "Patching: $name in namespace $namespace"
# Remove old annotation from pod template
    kubectl patch rediscluster "$name" -n "$namespace" \
        --type=json \
        -p '[{"op":"remove","path":"/spec/template/pod/metadata/annotations/redis.smartnews.com~1redis_insights_pi_blocker"}]' \
        2>/dev/null || true
# Move the tag, and remove label for requires_restart
    if kubectl patch rediscluster "$name" -n "$namespace" \
        --type=merge \
        -p "{\"metadata\":{\"annotations\":{\"redis.smartnews.com/redis_insights_pi_blocker\":\"$PI_BLOCKER_VALUE\"}}}" 2>&1; then
        kubectl label rediscluster "$name" -n "$namespace" 'redis.smartnews.com/requires_restart-' 2>/dev/null || true

        echo "✅ Successfully patched $namespace/$name"
        ((success++))
    else
        echo "❌ Failed to patch $namespace/$name"
        ((failed++))
    fi
done < "$CLUSTERS_FILE"

echo ""
echo "========================================"
echo "Summary"
echo "========================================"
echo "Total:   $total"
echo "Success: $success"
echo "Failed:  $failed"
echo ""
