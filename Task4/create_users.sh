#!/bin/bash

# Скрипт для создания пользователей Kubernetes через клиентские сертификаты (Minikube)
# Запускать из директории Task4

# Настройки Minikube (пути к CA ключам)
MINIKUBE_PROFILE="minikube"
CA_CERT="$HOME/.minikube/ca.crt"
CA_KEY="$HOME/.minikube/ca.key"

# Проверка наличия ключей CA
if [ ! -f "$CA_CERT" ] || [ ! -f "$CA_KEY" ]; then
    echo "Ошибка: Не найдены сертификаты CA Minikube по пути $HOME/.minikube/"
    echo "Убедитесь, что Minikube запущен (minikube start)"
    exit 1
fi

# Функция создания пользователя
create_user() {
    local USERNAME=$1
    local GROUP=$2
    local NAMESPACE=${3:-default}

    echo "Создание пользователя: $USERNAME (Группа: $GROUP)"

    # 1. Генерация приватного ключа
    openssl genrsa -out ${USERNAME}.key 2048

    # 2. Создание запроса на подпись сертификата (CSR)
    # CN = имя пользователя, O = группа (важно для RoleBinding)
    openssl req -new -key ${USERNAME}.key -out ${USERNAME}.csr -subj "/CN=${USERNAME}/O=${GROUP}"

    # 3. Подпись сертификата нашим CA (срок действия 365 дней)
    openssl x509 -req -in ${USERNAME}.csr -CA $CA_CERT -CAkey $CA_KEY -CAcreateserial -out ${USERNAME}.crt -days 365

    # 4. Настройка kubeconfig для этого пользователя
    # Получаем текущий контекст и кластер
    CURRENT_CONTEXT=$(kubectl config current-context)
    CLUSTER_NAME=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='$CURRENT_CONTEXT')].context.cluster}")
    CLUSTER_ENDPOINT=$(kubectl config view -o jsonpath="{.clusters[?(@.name=='$CLUSTER_NAME')].cluster.server}")

    # Создаем отдельный файл конфигурации для пользователя
    KUBECONFIG_FILE="${USERNAME}-kubeconfig.yaml"
    
    kubectl config --kubeconfig=$KUBECONFIG_FILE set-cluster $CLUSTER_NAME \
        --server=$CLUSTER_ENDPOINT \
        --certificate-authority=$CA_CERT \
        --embed-certs=true

    kubectl config --kubeconfig=$KUBECONFIG_FILE set-credentials $USERNAME \
        --client-certificate=${USERNAME}.crt \
        --client-key=${USERNAME}.key \
        --embed-certs=true

    kubectl config --kubeconfig=$KUBECONFIG_FILE set-context ${USERNAME}-context \
        --cluster=$CLUSTER_NAME \
        --user=$USERNAME \
        --namespace=$NAMESPACE

    kubectl config --kubeconfig=$KUBECONFIG_FILE use-context ${USERNAME}-context

    echo "Готово! Конфигурация для $USERNAME сохранена в $KUBECONFIG_FILE"
    echo "Проверить доступ можно командой: kubectl --kubeconfig=$KUBECONFIG_FILE auth can-i --list"
    echo "---------------------------------------------------"
}

# Создаем пользователей согласно таблице ролей
# Пользователь 1: Специалист по ИБ (Привилегированный доступ)
create_user "security-admin" "propdev-security-admins" "kube-system"

# Пользователь 2: Бизнес-аналитик (Только просмотр)
create_user "bi-analyst" "propdev-auditors" "default"

# Пользователь 3: DevOps-инженер домена ЖКУ (Управление в своем namespace)
# Сначала создадим namespace для примера, если его нет
kubectl get namespace zhku || kubectl create namespace zhku
create_user "zhku-devops" "propdev-devops" "zhku"

echo "Все пользователи успешно созданы!"