# Diagramas UML — muBench S6 (Simplificado)

> **Fecha:** 2026-05-14  
> Todos los diagramas están expresados en sintaxis **PlantUML**. Para renderizarlos: [https://plantuml.com](https://plantuml.com) o extensión PlantUML en VS Code.

---

## 1. Diagrama de Clases (Simplificado)

```plantuml
@startuml class_diagram
!theme plain
skinparam classBackgroundColor #FEFEFE
skinparam classBorderColor #555555

title "muBench S6 — Diagrama de Clases (Microservicios y Dominio)"

'=== DOMINIO DE AUTH ===
class AuthService {
  - jwt_secret: str
  - db: Optional[Database]
  + login(username: str, password: str): LoginResponse
  + validate_token(token: str): bool
  + health(): HealthStatus
  + metrics(): PrometheusMetrics
}

class LoginRequest {
  + username: str
  + password: str
}

class LoginResponse {
  + access_token: str
  + token_type: str = "bearer"
  + expires_in: int
}

class JwtPayload {
  + sub: str
  + iat: int
  + exp: int
  + jti: str
}

'=== DOMINIO DE API ===
class ApiService {
  - auth_base: str
  + get_profile(user_id: int, token: str): ProfileResponse
  + list_users(limit: int, offset: int, token: str): UsersResponse
  + health(): HealthStatus
  + metrics(): PrometheusMetrics
}

class ProfileResponse {
  + user: UserDTO
  + db_latency_ms: float
}

class UsersResponse {
  + users: List<UserDTO>
  + count: int
  + db_latency_ms: float
}

class UserDTO {
  + id: int
  + username: str
  + email: str
  + created_at: datetime
}

'=== DOMINIO DE DATA ===
class DataService {
  - db_host: str
  - db_port: int
  - db_name: str
  - pool: ConnectionPool
  + get_user_profile(user_id: int): UserRecord
  + list_users(limit: int, offset: int): List<UserRecord>
  + health(): HealthStatus
  + metrics(): PrometheusMetrics
}

class UserRecord {
  + id: int
  + username: str
  + password_hash: str
  + email: str
  + created_at: datetime
}

'=== INFRAESTRUCTURA ===
class PostgresDB {
  - host: str
  - port: int
  - name: str
  + query(sql: str, params: tuple): Result
  + connect(): Connection
  + close(): void
}

'=== OBSERVABILIDAD ===
class PrometheusMetrics {
  + http_requests_total: Counter
  + http_request_duration_seconds: Histogram
  + db_query_duration_seconds: Histogram
  + expose(): str
}

'=== RELACIONES ===
AuthService ..> LoginRequest : receives
AuthService ..> LoginResponse : returns
AuthService ..> JwtPayload : creates
ApiService ..> AuthService : validates token via HTTP
ApiService ..> DataService : fetches data via HTTP
ApiService ..> ProfileResponse : returns
ApiService ..> UsersResponse : returns
DataService ..> PostgresDB : uses
DataService ..> UserRecord : returns
AuthService ..> PrometheusMetrics : exposes
ApiService ..> PrometheusMetrics : exposes
DataService ..> PrometheusMetrics : exposes

@enduml
```

---

## 2. Diagrama Relacional de Base de Datos (Simplificado)

```plantuml
@startuml db_diagram
!theme plain
skinparam defaultFontSize 11

title "muBench S6 — Modelo Relacional (Simplificado)"

entity "users" as users {
  * id : SERIAL <<PK>>
  --
  * username : VARCHAR(64) <<UNIQUE, NOT NULL>>
  * password_hash : VARCHAR(255) <<NOT NULL>>
  * email : VARCHAR(128) <<UNIQUE>>
  * created_at : TIMESTAMP DEFAULT NOW()
  * is_active : BOOLEAN DEFAULT TRUE
}

entity "sessions" as sessions {
  * id : SERIAL <<PK>>
  --
  * user_id : INTEGER <<FK → users.id>>
  * jti : VARCHAR(64) <<UNIQUE, NOT NULL>>
  * issued_at : TIMESTAMP NOT NULL
  * expires_at : TIMESTAMP NOT NULL
  * revoked : BOOLEAN DEFAULT FALSE
}

entity "request_log" as reqlog {
  * id : BIGSERIAL <<PK>>
  --
  * service : VARCHAR(32) NOT NULL
  * method : VARCHAR(8) NOT NULL
  * path : VARCHAR(256) NOT NULL
  * status_code : INTEGER NOT NULL
  * duration_ms : FLOAT NOT NULL
  * timestamp : TIMESTAMP DEFAULT NOW()
  * user_id : INTEGER <<FK → users.id, nullable>>
}

'=== RELACIONES ===
users ||--o{ sessions : "has"
users ||--o{ reqlog : "generates (nullable)"

@enduml
```

---

## 3. Diagrama de Flujo — Ciclo de Vida de una Corrida (Simplificado)

```plantuml
@startuml flow_diagram
!theme plain
skinparam defaultFontSize 11

title "muBench S6 — Flujo de Ejecución de una Corrida (Simplificado)"

start

:Leer parámetros de campaña\n(control, variant, vus, replicate);

:Aplicar configuración de control\nkubectl apply -f {control_yaml};

:Warm-up (30s)\nEsperar que pods Ready;

fork
  :Port-forward auth-service\nlocalhost:8084 → auth-service:8080;
fork again
  :Port-forward api-service\nlocalhost:8085 → api-service:8080;
end fork

:Iniciar k6\n--vus {vus} --duration {60s}\n--out json={output_file};

:k6 escribe métricas en NDJSON\n(una línea por evento);

:Cooldown (15s)\nMatar port-forwards;

:Consultar Prometheus\nQueryRange(cpu_mcores, mem_mib)\ndurante ventana de la corrida;

:Guardar resultado completo\n{campaign_id}_{...}_{vus}vus.json;

if (Archivo ya existía?) then (yes)
  :Skip (datos intactos);
else (no)
  :Continuar con siguiente fila;
endif

:¿Quedan filas en la matriz\nde experimento?;

if (Sí) then
  :Siguiente fila (control/variant/vus/replica);
  :Volver al inicio;
else (No)
  :Ejecutar pipeline de análisis\nextract_clean_metrics.py\ns6_statistical_analysis_rigorous.py;
  :Generar reportes\nCSV, Markdown, PNG;
  stop
endif

@enduml
```

---

## Cómo Renderizar

### Opción 1 — VS Code
Instala la extensión `PlantUML` (jebbs.plantuml), abre cualquiera de los bloques de código anteriores en un archivo `.puml` y presiona `Alt+D`.

### Opción 2 — Online
1. Copia el contenido entre `@startuml` y `@enduml`
2. Pega en [https://plantuml.com/plantuml](https://www.plantuml.com/plantuml/uml/)
3. El diagrama se renderiza automáticamente

### Opción 3 — CLI
```bash
java -jar plantuml.jar documentecionFinal/05_diagramas_uml.md
# Genera: documentecionFinal/05_diagramas_uml.png
```
