# Contexto del Miniproyecto Neoris

## ¿Qué es este proyecto?
Proyecto de aprendizaje para practicar Docker, GitHub Actions, Kubernetes, Kustomize, Helm y Terraform.
La app es una API REST en Node.js (Express) con base de datos PostgreSQL y Redis, desplegada en Minikube.

---

## Entorno
- OS: Windows con WSL2 (Ubuntu)
- Minikube, kubectl, Helm y Terraform instalados en **WSL**
- Freelens instalado en **Windows via Scoop**
- Git y desarrollo desde WSL

---

## Lo que está hecho

### 1. Dockerfile
Archivo: `Dockerfile`
- Imagen base: `node:18-alpine`
- Copia `package.json` y ejecuta `npm install --omit=dev`
- Copia `index.js` y arranca con `node index.js`
- Expone el puerto 3000
- `.dockerignore` excluye `node_modules/`, `k8s/`, `helm/`, `terraform/`, `.git/`

> El Dockerfile es solo para la app Node.js. PostgreSQL y Redis usan sus imágenes oficiales directamente en los manifiestos.

### 2. GitHub Actions — CI/CD completo
Archivo: `.github/workflows/docker-publish.yml`
- Se dispara en cada push a `main`
- **Job `build-and-push`** (runner GitHub `ubuntu-latest`):
  - Hace login en `ghcr.io` con el `GITHUB_TOKEN` automático
  - Construye la imagen y la sube con dos tags: `latest` y `sha-<commit>`
  - Imagen resultante: `ghcr.io/givencloud/miniproyecto_neoris:sha-<commit>`
  - El repositorio es **privado**
  - Expone la tag SHA generada como job output (`image_tag`)
- **Job `deploy`** (self-hosted runner en WSL2):
  - Solo arranca si `build-and-push` termina correctamente (`needs: build-and-push`)
  - Ejecuta `helm upgrade --install miniproyecto ./helm/miniproyecto --namespace miniproyecto --create-namespace --set web.image=...:sha-<commit>` — usa la tag exacta recién construida, no `latest`
  - Espera a que el rollout complete con `kubectl rollout status deployment/web-deployment --namespace miniproyecto --timeout=120s`

### 3. API REST — `index.js`
Stack: Node.js + Express + `pg` (cliente PostgreSQL)

**Endpoints:**
- `GET /health` → devuelve `{ status: 'ok' }` si la DB responde, `503` si no — usado por las Probes de Kubernetes
- `GET /` → devuelve HTML con "Hola 👋"
- `GET /users` → devuelve todos los usuarios en JSON
- `POST /users` → crea un usuario (body: `{ "name": "...", "email": "..." }`)

**Características:**
- Conexión a PostgreSQL mediante variables de entorno (`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`)
- `initDB()` al arrancar: crea la tabla `users` si no existe e inserta datos de ejemplo (Alice y Bob)
- Reintentos en la conexión a DB (10 intentos, 3s entre cada uno) — necesario porque PostgreSQL tarda en levantar
- `try/catch` en todas las rutas async → devuelve `500` con mensaje claro si falla la DB
- Validación de input en `POST /users` → devuelve `400` si falta `name` o `email`
- Queries con parámetros preparados (`$1, $2`) → protección contra SQL injection

### 4. Manifiestos de Kubernetes
Carpeta: `k8s/base/` — organizada en subcarpetas por servicio

**web/deployment.yaml** — App Node.js
- Nombre: `web-deployment`
- Label: `app: web-server`
- 2 réplicas (valor base, sobreescrito por Kustomize)
- Imagen: `ghcr.io/givencloud/miniproyecto_neoris:latest`
- Usa `imagePullSecrets` con el secret `ghcr-secret` (necesario porque el repo es privado)
- Inyecta todas las variables de entorno de DB con `envFrom` (ConfigMap `postgres-config` + Secret `postgres-secret`)
- Resources: requests 100m CPU / 128Mi RAM, limits 500m CPU / 256Mi RAM
- **Readiness Probe**: `GET /health` cada 5s
- **Liveness Probe**: `GET /health` cada 10s

**web/service.yaml** — App Node.js
- Nombre: `web-service`
- Tipo: `NodePort` (accesible desde fuera del cluster)
- Puerto externo: 30080 → Puerto interno: 80 → Puerto del contenedor: 3000
- Puerto nombrado `http`

**postgres/postgres-deployment.yaml** — PostgreSQL
- Nombre: `postgres-deployment`
- Imagen: `postgres:15-alpine`
- Variables de entorno leídas del ConfigMap `postgres-config` y Secret `postgres-secret`
- Resources: requests 100m CPU / 256Mi RAM, limits 500m CPU / 512Mi RAM
- **Readiness Probe**: `pg_isready` cada 5s
- **Liveness Probe**: `pg_isready` cada 10s

**postgres/postgres-service.yaml** — PostgreSQL
- Nombre: `postgres-service`
- Tipo: `ClusterIP` (solo accesible dentro del cluster)
- Puerto: 5432

**postgres/postgres-configmap.yaml** — Configuración de la DB (no sensible)
```
DB_HOST: postgres-service
DB_PORT: 5432
DB_NAME: appdb
```

**postgres/postgres-secret.yaml** — Credenciales de la DB (sensible)
```
DB_USER: appuser
DB_PASSWORD: apppassword
```
> Este archivo está en `.gitignore` y nunca se commitea. Usar `postgres-secret.example.yaml` como plantilla. Crearlo con `cp postgres-secret.example.yaml postgres-secret.yaml` y editar los valores.

**redis/redis-deployment.yaml** — Redis
- Nombre: `redis-deployment`
- Imagen: `redis:7-alpine`
- Resources: requests 50m CPU / 64Mi RAM, limits 200m CPU / 128Mi RAM
- **Readiness Probe**: `redis-cli ping` cada 5s
- **Liveness Probe**: `redis-cli ping` cada 10s

**redis/redis-service.yaml** — Redis
- Nombre: `redis-service`
- Tipo: `ClusterIP`
- Puerto: 6379

### 5. Helm Chart
Carpeta: `helm/miniproyecto/`

```
helm/miniproyecto/
├── Chart.yaml              ← metadatos del chart (nombre, versión, type, appVersion)
├── values.yaml             ← todos los valores configurables con sus defaults (incluye resources)
└── templates/
    ├── web/
    │   ├── deployment.yaml     ← web app
    │   └── service.yaml        ← NodePort (puerto nombrado "http")
    ├── postgres/
    │   ├── deployment.yaml     ← PostgreSQL
    │   └── service.yaml        ← ClusterIP
    └── redis/
        ├── deployment.yaml     ← Redis
        └── service.yaml        ← ClusterIP
```

Los templates usan `{{ .Values.xxx }}` para referenciar valores de `values.yaml`.
`values.yaml` incluye bloques `resources` para los tres servicios (web, db, redis).
`DB_HOST` se configura via `{{ .Values.db.host }}` (valor: `postgres-service`).

**Comandos Helm:**
```bash
# Ver qué generaría Helm sin aplicar
helm template miniproyecto ./helm/miniproyecto

# Instalar o actualizar
helm upgrade --install miniproyecto ./helm/miniproyecto

# Sobreescribir un valor puntualmente
helm upgrade --install miniproyecto ./helm/miniproyecto --set web.replicas=2

# Ver releases instaladas
helm list

# Desinstalar todo
helm uninstall miniproyecto
```

### 6. Terraform
Carpeta: `terraform/`

```
terraform/
├── main.tf        ← provider de Kubernetes apuntando a Minikube
├── variables.tf   ← todas las variables con valores por defecto
├── web.tf         ← kubernetes_deployment + kubernetes_service de la app
└── database.tf    ← kubernetes_config_map + kubernetes_deployment + kubernetes_service de PostgreSQL
```

Los recursos usan `var.xxx` para referenciar variables de `variables.tf`.
`.terraform/` y `terraform.tfstate` están en `.gitignore`. `terraform.lock.hcl` sí se commitea.

**Comandos Terraform:**
```bash
cd terraform/

# Descargar el provider de Kubernetes (solo la primera vez)
terraform init

# Ver qué va a crear/modificar/borrar (sin aplicar)
terraform plan

# Aplicar los cambios en Minikube
terraform apply

# Sobreescribir una variable puntualmente
terraform apply -var="web_replicas=2"

# Borrar todos los recursos gestionados por Terraform
terraform destroy
```

### 7. Kustomize
Estructura:
```
k8s/
├── base/
│   ├── kustomization.yaml          ← referencia ./web, ./postgres, ./redis
│   ├── web/
│   │   ├── kustomization.yaml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── postgres/
│   │   ├── kustomization.yaml
│   │   ├── postgres-deployment.yaml
│   │   ├── postgres-service.yaml
│   │   ├── postgres-configmap.yaml
│   │   └── postgres-secret.example.yaml  ← plantilla commiteada
│   └── redis/
│       ├── kustomization.yaml
│       ├── redis-deployment.yaml
│       └── redis-service.yaml
└── overlays/
    ├── development/
    │   ├── kustomization.yaml
    │   └── patch.yaml        → réplicas: 1
    └── production/
        ├── kustomization.yaml
        └── patch.yaml        → réplicas: 2
```

> `postgres-secret.yaml` está en `.gitignore` y nunca se commitea. Usar `postgres-secret.example.yaml` como plantilla. Crearlo manualmente antes del primer deploy con `kubectl apply -k`.
> Cada subcarpeta tiene su propio `kustomization.yaml` — el de `base/` recoge las tres carpetas en cascada.

---

## Flujo de comunicación en el cluster

```
Internet
   │
   │ puerto 30080
   ▼
web-service (NodePort)
   │
   ▼
web-deployment (Node.js + Express)
   ├── SQL queries · puerto 5432 ──→ postgres-service (ClusterIP)
   │                                        │
   │                                        ▼
   │                                 postgres-deployment (PostgreSQL)
   │
   └── caché · puerto 6379 ──────→ redis-service (ClusterIP)
                                           │
                                           ▼
                                    redis-deployment (Redis)
```

Los pods se comunican por nombre de Service, no por IP. Kubernetes resuelve el nombre al pod correcto mediante DNS interno.

---

## Comandos útiles

### Instalar el self-hosted runner en WSL2
```bash
# 1. En GitHub: Settings → Actions → Runners → New self-hosted runner → Linux / x64
#    Copia la URL de descarga y el token de registro que te da GitHub

# 2. En WSL:
mkdir ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64.tar.gz -L <URL_QUE_DA_GITHUB>
tar xzf ./actions-runner-linux-x64.tar.gz
./config.sh --url https://github.com/GivenCloud/Miniproyecto_Neoris --token <TOKEN>

# 3. Instalar como servicio systemd (arranca con WSL automáticamente)
sudo ./svc.sh install
sudo ./svc.sh start

# Verificar que el runner aparece como "Idle" en GitHub → Settings → Actions → Runners
```

> Pre-requisitos en el cluster antes del primer deploy automático:
> - `minikube start`
> - `kubectl create secret docker-registry ghcr-secret ...` (ver sección siguiente)

### Desplegar en Minikube
```bash
# Arrancar Minikube
minikube start

# Crear el secret de GHCR para descargar la imagen privada (en el namespace correcto)
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=GivenCloud \
  --docker-password=TU_PAT \
  --namespace miniproyecto

# Desplegar con Helm (método actual — el pipeline hace esto automáticamente)
helm upgrade --install miniproyecto ./helm/miniproyecto --namespace miniproyecto --create-namespace

# Verificar pods
kubectl get pods -n miniproyecto -w

# Acceder a la app
minikube service web-service -n miniproyecto --url
```

> **IMPORTANTE:** Helm es ahora el único gestor de recursos en el cluster. No mezclar con `kubectl apply -k` — si se despliega con Kustomize primero y luego con Helm, el pipeline fallará con error de "invalid ownership metadata". Si ocurre, limpiar con `kubectl delete -k k8s/overlays/development` antes de volver a usar Helm.

### Probar los endpoints
```bash
# Comprobar health
curl http://<MINIKUBE_URL>/health

# Listar usuarios
curl http://<MINIKUBE_URL>/users

# Crear usuario
curl -X POST http://<MINIKUBE_URL>/users \
  -H "Content-Type: application/json" \
  -d '{"name": "Carlos", "email": "carlos@example.com"}'

# Probar validación (debe devolver 400)
curl -X POST http://<MINIKUBE_URL>/users \
  -H "Content-Type: application/json" \
  -d '{"name": "Solo nombre"}'
```

### Diagnóstico
```bash
# Logs de la app
kubectl logs deployment/web-deployment -n miniproyecto

# Logs de PostgreSQL
kubectl logs deployment/postgres-deployment -n miniproyecto

# Logs de Redis
kubectl logs deployment/redis-deployment -n miniproyecto

# Eventos del cluster
kubectl get events -n miniproyecto --sort-by='.lastTimestamp'

# Describir un pod con problemas
kubectl describe pod <nombre-del-pod> -n miniproyecto

# Ver qué generaría Kustomize sin aplicar
kubectl kustomize k8s/overlays/development
```

---

## Pendiente

- **Freelens**: Freelens está instalado en Windows pero Minikube está en WSL, por lo que no detecta el cluster automáticamente.

---

## Próximos pasos de aprendizaje

### Orden acordado (prioridad real para trabajar de DevOps)

1. ~~**Ampliar el backend**~~ ✅ — API REST con Express + PostgreSQL
2. ~~**Liveness y Readiness Probes**~~ ✅ — Readiness evita tráfico hasta que el pod esté listo, Liveness reinicia el pod si se queda colgado.
3. ~~**ConfigMaps y Secrets**~~ ✅ — implementados para las credenciales de la DB.
4. ~~**CI/CD completo**~~ ✅ — self-hosted runner en WSL2. Pipeline completo: push → build → push imagen → deploy automático con tag SHA exacta. Job `deploy` espera a `build-and-push` y verifica el rollout.
5. ~~**Helm**~~ ✅ — chart propio con subcarpetas por servicio (web/postgres/redis), `values.yaml` con resources y `db.host`. Pipeline usa la tag SHA del build.
6. ~~**Terraform + Minikube**~~ ✅ — provider de Kubernetes apuntando a Minikube. 4 archivos HCL (main, variables, web, database). Flujo completo: init → plan → apply → destroy.

### Pasos técnicos pendientes del proyecto actual
- **Ingress** — punto de entrada único con rutas en lugar de NodePort
- **PVC** — volumen persistente para PostgreSQL (actualmente los datos se pierden al reiniciar el pod)
- **Horizontal Pod Autoscaler** — escalar réplicas automáticamente según carga
- **Namespaces** — separar recursos por entorno dentro del cluster
- **ArgoCD** — GitOps, el cluster se gestiona a sí mismo vigilando el repositorio. Aprenderlo cuando sea necesario en el trabajo

---

## GitHub
- Repositorio: https://github.com/GivenCloud/Miniproyecto_Neoris
- Rama principal: `main`
- Registro de imágenes: `ghcr.io/givencloud/miniproyecto_neoris`
