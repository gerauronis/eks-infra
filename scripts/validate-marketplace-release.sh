#!/bin/bash

# Script de Validación Post-Release para Marketplace Service
# Uso: ./validate-marketplace-release.sh [ambiente]
# Ejemplo: ./validate-marketplace-release.sh develop

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuración
ENVIRONMENT=${1:-develop}
NAMESPACE="kometa-${ENVIRONMENT}"
SERVICE_NAME="kometa-marketplace"
BASE_URL="https://marketplace.kometadeveloper.xyz"

# Función para logging
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Función para verificar comando
check_command() {
    if ! command -v $1 &> /dev/null; then
        error "Comando $1 no encontrado. Por favor instálalo."
        exit 1
    fi
}

# Verificar dependencias
check_dependencies() {
    log "Verificando dependencias..."
    check_command kubectl
    check_command curl
    check_command jq
    success "Dependencias verificadas"
}

# Verificar conectividad con cluster
check_cluster() {
    log "Verificando conectividad con cluster..."
    if kubectl cluster-info &> /dev/null; then
        success "Cluster accesible"
    else
        error "No se puede conectar al cluster"
        exit 1
    fi
}

# Verificar namespace
check_namespace() {
    log "Verificando namespace $NAMESPACE..."
    if kubectl get namespace $NAMESPACE &> /dev/null; then
        success "Namespace $NAMESPACE existe"
    else
        error "Namespace $NAMESPACE no existe"
        exit 1
    fi
}

# Verificar deployment
check_deployment() {
    log "Verificando deployment $SERVICE_NAME..."
    
    # Verificar si el deployment existe
    if ! kubectl get deployment $SERVICE_NAME -n $NAMESPACE &> /dev/null; then
        error "Deployment $SERVICE_NAME no existe en namespace $NAMESPACE"
        return 1
    fi
    
    # Verificar estado del deployment
    READY=$(kubectl get deployment $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
    DESIRED=$(kubectl get deployment $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.replicas}')
    
    if [ "$READY" = "$DESIRED" ]; then
        success "Deployment $SERVICE_NAME está listo ($READY/$DESIRED)"
    else
        error "Deployment $SERVICE_NAME no está listo ($READY/$DESIRED)"
        return 1
    fi
}

# Verificar pods
check_pods() {
    log "Verificando pods del servicio..."
    
    PODS=$(kubectl get pods -n $NAMESPACE -l app=$SERVICE_NAME -o jsonpath='{.items[*].metadata.name}')
    
    for pod in $PODS; do
        STATUS=$(kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.status.phase}')
        if [ "$STATUS" = "Running" ]; then
            success "Pod $pod está en estado Running"
        else
            error "Pod $pod está en estado $STATUS"
            kubectl describe pod $pod -n $NAMESPACE
            return 1
        fi
    done
}

# Verificar service
check_service() {
    log "Verificando service..."
    
    if kubectl get service $SERVICE_NAME -n $NAMESPACE &> /dev/null; then
        success "Service $SERVICE_NAME existe"
        
        # Verificar endpoints
        ENDPOINTS=$(kubectl get endpoints $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.subsets[*].addresses[*].ip}')
        if [ -n "$ENDPOINTS" ]; then
            success "Service tiene endpoints: $ENDPOINTS"
        else
            error "Service no tiene endpoints"
            return 1
        fi
    else
        error "Service $SERVICE_NAME no existe"
        return 1
    fi
}

# Verificar ingress
check_ingress() {
    log "Verificando ingress..."
    
    INGRESS_NAME=$(kubectl get ingress -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')
    if [ -n "$INGRESS_NAME" ]; then
        success "Ingress $INGRESS_NAME encontrado"
        
        # Verificar que el ingress tenga la configuración correcta
        HOST=$(kubectl get ingress $INGRESS_NAME -n $NAMESPACE -o jsonpath='{.spec.rules[?(@.host=="marketplace.kometadeveloper.xyz")].host}')
        if [ "$HOST" = "marketplace.kometadeveloper.xyz" ]; then
            success "Ingress configurado para marketplace.kometadeveloper.xyz"
        else
            error "Ingress no configurado correctamente para marketplace.kometadeveloper.xyz"
            return 1
        fi
    else
        error "No se encontró ingress en namespace $NAMESPACE"
        return 1
    fi
}

# Verificar health check
check_health() {
    log "Verificando health check..."
    
    # Intentar health check con timeout
    if curl -f -s --max-time 10 "$BASE_URL/health" > /dev/null; then
        success "Health check exitoso"
    else
        error "Health check falló"
        return 1
    fi
}

# Verificar API endpoints
check_api_endpoints() {
    log "Verificando endpoints de API..."
    
    # Health check con respuesta JSON
    HEALTH_RESPONSE=$(curl -s --max-time 10 "$BASE_URL/health")
    if echo "$HEALTH_RESPONSE" | jq . > /dev/null 2>&1; then
        success "Health endpoint responde con JSON válido"
        
        # Verificar versión en health check
        VERSION=$(echo "$HEALTH_RESPONSE" | jq -r '.version // .Version // "unknown"')
        log "Versión detectada: $VERSION"
    else
        warning "Health endpoint no responde con JSON válido"
    fi
    
    # Verificar endpoint de productos (si existe)
    if curl -f -s --max-time 10 "$BASE_URL/api/v1/products" > /dev/null 2>&1; then
        success "Endpoint /api/v1/products responde"
    else
        warning "Endpoint /api/v1/products no responde (puede ser normal si requiere autenticación)"
    fi
}

# Verificar logs
check_logs() {
    log "Verificando logs de los pods..."
    
    PODS=$(kubectl get pods -n $NAMESPACE -l app=$SERVICE_NAME -o jsonpath='{.items[*].metadata.name}')
    
    for pod in $PODS; do
        log "Revisando logs del pod $pod..."
        
        # Verificar errores críticos en los últimos 100 logs
        ERROR_COUNT=$(kubectl logs $pod -n $NAMESPACE --tail=100 2>/dev/null | grep -i "error\|exception\|fatal" | wc -l)
        
        if [ "$ERROR_COUNT" -eq 0 ]; then
            success "No se encontraron errores críticos en logs de $pod"
        else
            warning "Se encontraron $ERROR_COUNT posibles errores en logs de $pod"
            kubectl logs $pod -n $NAMESPACE --tail=50 | grep -i "error\|exception\|fatal" || true
        fi
    done
}

# Verificar recursos
check_resources() {
    log "Verificando uso de recursos..."
    
    PODS=$(kubectl get pods -n $NAMESPACE -l app=$SERVICE_NAME -o jsonpath='{.items[*].metadata.name}')
    
    for pod in $PODS; do
        log "Revisando recursos del pod $pod..."
        
        # Verificar uso de CPU y memoria
        RESOURCES=$(kubectl top pod $pod -n $NAMESPACE 2>/dev/null || echo "N/A")
        if [ "$RESOURCES" != "N/A" ]; then
            success "Recursos del pod $pod: $RESOURCES"
        else
            warning "No se pudieron obtener métricas de recursos para $pod"
        fi
    done
}

# Verificar métricas de New Relic (si está disponible)
check_newrelic() {
    log "Verificando integración con New Relic..."
    
    # Verificar si New Relic está configurado
    if kubectl get deployment -n $NAMESPACE | grep -q newrelic; then
        success "New Relic está desplegado en el namespace"
    else
        warning "New Relic no está desplegado en el namespace"
    fi
}

# Función principal
main() {
    echo "=========================================="
    echo "Validación Post-Release - Marketplace Service"
    echo "Ambiente: $ENVIRONMENT"
    echo "Namespace: $NAMESPACE"
    echo "URL: $BASE_URL"
    echo "=========================================="
    echo ""
    
    # Ejecutar verificaciones
    check_dependencies
    check_cluster
    check_namespace
    check_deployment
    check_pods
    check_service
    check_ingress
    check_health
    check_api_endpoints
    check_logs
    check_resources
    check_newrelic
    
    echo ""
    echo "=========================================="
    success "Validación completada exitosamente!"
    echo "=========================================="
    echo ""
    echo "Próximos pasos:"
    echo "1. Ejecutar pruebas manuales de funcionalidad"
    echo "2. Verificar integración con otros servicios"
    echo "3. Monitorear métricas durante las próximas horas"
    echo "4. Documentar cualquier problema encontrado"
}

# Manejo de errores
trap 'error "Error en línea $LINENO. Comando: $BASH_COMMAND"' ERR

# Ejecutar función principal
main "$@" 