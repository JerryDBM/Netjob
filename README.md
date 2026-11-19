# NetJob

Marketplace colombiano de servicios para el hogar y pequeños negocios: conecta clientes con trabajadores independientes (plomería, electricidad, carpintería, pintura, cerrajería…).

```
backend/   API REST + tiempo real — Node.js, Express 5, Prisma, PostgreSQL, Socket.IO, Wompi
app/       App Flutter (Android, iOS, Web, Windows) — cliente, profesional y resumen admin
```

## Puesta en marcha (desarrollo)

Requisitos: Node 20+ y Flutter 3.41+. No hace falta instalar PostgreSQL: el script `db:dev` levanta uno embebido.

```bash
cd backend
npm install
cp .env.example .env
npm run db:dev        # deja esta terminal abierta (PostgreSQL en el puerto 5433)
```

En otra terminal:

```bash
cd backend
npm run db:push       # crea o actualiza las tablas
npm run db:seed       # categorías, planes y cuentas demo (también renueva las suscripciones demo vencidas)
npm run dev           # API en http://localhost:4000
npm test              # prueba de extremo a extremo del flujo completo
```

App:

```bash
cd app
flutter run -d chrome --dart-define=MAPS_API_KEY=AIza...      # web con Google Maps
flutter run -d windows                                         # escritorio (sin mapa: vista aproximada)
flutter run --dart-define=API_URL=http://192.168.1.10:4000 --dart-define=MAPS_API_KEY=AIza...   # celular en la misma red
```

Atajo: `app/config/dev.json` ya tiene la URL de la API en la red local y la llave web de Maps:

```bash
flutter build web --dart-define-from-file=config/dev.json
```

En el emulador de Android la app usa `http://10.0.2.2:4000` automáticamente. En Android la llave de Maps también va en `app/android/local.properties` como `MAPS_API_KEY=AIza...`.

Sin `MAPS_API_KEY` la app funciona igual y muestra una vista aproximada (anillos de 4, 8 y 12 km) en lugar del mapa.

**Ubicación en el celular por web:** los navegadores solo comparten la ubicación por `https` (o `localhost`). Si abres la app por `http://192.168.x.x`, el cliente debe elegir su ciudad a mano o usar un túnel https.

**Probar la búsqueda desde tu ciudad:** los profesionales demo están en Bogotá y Medellín. Para moverlos cerca de ti:

```bash
cd backend
npm run demo:near -- 10.3910 -75.4794 "Cartagena"
```

O crear 5 profesionales demo nuevos (completos y con plan activo) alrededor de un punto. Ya están creados en El Carmen de Bolívar (`demo-carmen-1@netjob.co` … `demo-carmen-5@netjob.co`, contraseña `NetJob2026!`):

```bash
npm run demo:seed-near -- 9.7174 -75.1202 "El Carmen de Bolívar" carmen
```

### Cuentas demo (contraseña `NetJob2026!`)

| Rol | Correo |
|---|---|
| Cliente | cliente@netjob.co |
| Profesional (Premium, Bogotá) | plomero@netjob.co |
| Profesional (Intermedio, Bogotá) | electricista@netjob.co |
| Profesional (Básico, Medellín) | carpintero@netjob.co |
| Administrador | admin@netjob.co |

## Qué incluye esta entrega (MVP del flujo completo)

1. **Registro e inicio de sesión** con tipo de cuenta (cliente / profesional), recuperación de contraseña y edición de datos. El rol administrador no se puede elegir en el registro público.
2. **Perfil profesional obligatorio**: al registrarse, el profesional no puede usar la app hasta completar foto de perfil, título, descripción, especialidades, zona de trabajo (ciudad, barrios y punto en el mapa), horarios y al menos 2 fotos de portafolio (`MIN_PORTFOLIO`). Un perfil incompleto no aparece en búsquedas. El teléfono no se expone en el perfil público.
3. **Servicios con precio "desde"**: el precio publicado es de referencia (cada caso cambia según materiales y complejidad). Límites de servicios según el plan.
4. **Búsqueda por ubicación (12 km)**: la app toma la ubicación actual del cliente (GPS o navegador) y la sigue actualizando; solo muestra profesionales a máximo `SEARCH_RADIUS_KM` (12 km). Sin ubicación no se muestra a nadie (el cliente puede elegir su ciudad a mano). Mapa de Google Maps con el radio y los profesionales. Filtros: texto, categoría, precio, calificación, día y "disponible ahora". Solo aparecen profesionales con suscripción vigente y perfil completo.
5. **Solicitudes** con estados Pendiente → Aceptada / Rechazada → En proceso → Finalizada, y Cancelada. Dentro de "Aceptada" hay etapas: **pago de la visita de diagnóstico → diagnóstico y cotización → pago del valor final**. Cada cambio queda en el historial. El cliente ve sus servicios en espera y contratados en el inicio, y desde el detalle siempre puede volver al inicio.
6. **Chat** por solicitud en tiempo real (Socket.IO, con respaldo por consulta periódica). Se cierra al terminar la solicitud.
7. **Pagos con Wompi en dos momentos**:
   1. **Visita de diagnóstico** con el valor que fija cada profesional en su perfil (de $0 —gratis— a $35.000, `MAX_DIAGNOSTIC_FEE`; sin comisión) cuando el profesional acepta. Si es gratis, se pasa directo a la cotización.
   2. **Valor final cotizado** por el profesional después de revisar, más la comisión del 3 % (100.000 → 3.000 → total 103.000). El profesional puede corregir la cotización mientras el cliente no haya pagado.

   El backend crea la referencia, firma la integridad y devuelve la URL del Web Checkout. El estado se confirma por webhook con firma y, como respaldo, consultando a Wompi; nunca se confía en la app. Se valida el monto.

   **Pago retenido:** el valor del servicio queda retenido por NetJob y se libera al profesional cuando ambas partes confirman que el trabajo terminó (así lo plantean los workshops de canales). Un servicio ya pagado no se cancela directamente: se abre una reclamación y el administrador decide si se devuelve al cliente o se libera al profesional. La visita de diagnóstico se libera de inmediato.
8. **Calificaciones en ambos sentidos**: el cliente califica al profesional y el profesional califica al cliente (de 1 a 5, una vez por servicio finalizado). Cada uno tiene su pantalla de reseñas con anillo de 0 a 5, barras por estrellas y opiniones. El profesional ve la calificación del cliente en cada solicitud; las reseñas de un cliente solo las ven él mismo y los profesionales. Las reseñas se pueden reportar. Datos de ejemplo: `npm run demo:reviews`.
9. **Historiales**: solicitudes por estado, pagos (el cliente ve lo que pagó; el profesional ve sus ingresos sin la comisión), suscripciones.
10. **Notificaciones** en la app y en tiempo real (nuevas solicitudes, cambios de estado, mensajes, pagos, reseñas, suscripción). Los correos se registran en consola (falta conectar un proveedor).
11. **Suscripciones**: Básico $24.900, Intermedio $44.900, Premium $69.900. Elegir, pagar, renovar (suma 30 días) o cambiar de plan (inicia hoy). Vencimiento automático.
12. **Administración**: panel dentro de la app con pestañas de resumen, verificaciones, reclamaciones, usuarios (revisión y suspensión), reseñas reportadas, pagos y transacciones (filtros y totales), categorías, planes y promociones, y configuración general.

## Tercera entrega: agenda y herramientas del administrador

25. **Agenda de citas** (pestaña *Agenda*, cliente y profesional): vista por mes, semana o día con la hora, la dirección, la otra persona y qué hay que hacer en cada cita. Desde cada cita se puede:
    - **Reprogramar**: una parte propone otra fecha y hora; la otra la acepta o la rechaza (queda en el historial y se avisa a ambos).
    - **Nota privada** (ej. "llevar escalera"): solo la ve quien la escribe.
    - **Bloqueos del profesional** (vacaciones, compromisos): en esos días no le pueden pedir ni mover citas; el cliente ve esos días deshabilitados al elegir la fecha. No se puede bloquear encima de citas ya aceptadas.
26. **Recordatorios de citas**: un día antes y una hora antes, a ambas partes (al profesional también si una solicitud para mañana sigue sin respuesta).
27. **Valor de la visita de diagnóstico por profesional** (ver punto 7).
28. **Administración ampliada**: categorías (crear, editar, activar), pagos y transacciones con filtros y totales, y **configuración general** editable sin redesplegar (comisión, tarifa reducida, radio de búsqueda, garantía, tope de la visita, fotos mínimas, puntaje de la capacitación, umbral de revisión, duración de la suscripción).
29. **50 profesionales de prueba**, todos en Cartagena y repartidos por 20 barrios (máximo 9 km del centro), con descripción detallada, servicios, portafolio con fotos, horarios, plan activo y reseñas (`demo-pro-01@netjob.co` … `demo-pro-50@netjob.co`, contraseña `NetJob2026!`). Las fotos son de Flickr con licencia Creative Commons (créditos en cada foto del portafolio).

## Segunda entrega: confianza, seguimiento y beneficios

13. **"Voy en camino" y seguimiento en vivo**: en la pantalla de ruta el profesional toca *Voy en camino*; el cliente recibe el aviso y ve en un mapa por dónde va, a qué distancia y a qué hora llega. La ubicación solo se comparte entre la salida y la llegada (o hasta que el profesional termine la navegación); después se borra. Llegada automática a menos de 40 m o con el botón *Ya llegué*.
14. **Capacitación inicial obligatoria**: cuatro instructivos (atención al cliente, cumplimiento y cobros, seguridad, reglas de NetJob), aceptación de reglas y cuestionario de 25 preguntas (se aprueba con 20). Sin aprobarla el perfil no aparece en búsquedas. Los instructivos quedan en *Cuenta → Instructivos y reglas*. Contenido en `backend/src/lib/training.ts`.
15. **Verificación de identidad y antecedentes**: el profesional sube cédula (frente y reverso), selfie y certificado de antecedentes; el administrador aprueba o rechaza con motivo. Los documentos se guardan en `backend/private-uploads`, no son archivos públicos y solo los ven el dueño y el administrador. Es **obligatoria**: sin aprobación el perfil no aparece en búsquedas ni recibe solicitudes. No hay integración con Truora/TusDatos: la revisión es manual.
16. **Reclamaciones y garantía**: cualquiera de las dos partes abre una reclamación desde la solicitud (calidad, incumplimiento, cobros no pactados, conducta, daños, garantía, pagos). Mientras esté abierta, el servicio no se puede finalizar y el dinero sigue retenido. El administrador resuelve: devolver al cliente, liberar al profesional, visita de garantía o remitir a la aseguradora. Al finalizar un servicio empiezan 30 días de garantía sobre la mano de obra. La aseguradora es un estado del caso: no hay integración con una aseguradora real.
17. **Seguimiento de calidad**: una cuenta (profesional o cliente) entra "en revisión" si su promedio baja de 3,5 con al menos tres reseñas. El administrador puede suspender temporalmente (7, 15 o 30 días) o indefinidamente con motivo; la suspensión temporal se levanta sola.
18. **Fidelización y referidos**: cada 3 servicios finalizados, un cliente con calificación mayor a 4,4 gana un servicio con tarifa NetJob del 1 % en lugar del 3 %. Cada usuario tiene un código de invitación: el cliente invitado paga 1 % en su primer servicio y, al terminarlo, quien lo invitó gana lo mismo. El profesional siempre recibe el valor completo.
19. **Premios al profesional**: con calificación de 4,8 o más (mínimo 3 reseñas) y 3 servicios finalizados en 30 días obtiene 10 % de descuento en su siguiente suscripción (12 % con 6 servicios) y un potenciador de recomendación de 30 días (sube en los resultados y lleva la etiqueta "Recomendado"). Invitar a otro profesional que active su plan da 7 días de potenciador.
20. **Recomendados para ti**: en el inicio del cliente, profesionales cercanos según lo que ya contrató; primero los que ya le trabajaron.
21. **Perfil destacado pagado**: el profesional compra 7, 15 o 30 días destacados ($14.900, $24.900, $39.900; precios editables por el administrador).
22. **Comprobante de pago** por cada pago aprobado (número, concepto, valores, tarifa aplicada, estado del dinero y garantía). No es factura electrónica.
23. **Soporte por WhatsApp Business** al +57 302 740 2932 (`SUPPORT_WHATSAPP` en el backend y `app/lib/core/support.dart` en la app).
24. **Mapa en estilo claro** (`app/lib/core/maps.dart`).

### Beneficios de cada plan (los aplica el backend)

| | Básico $24.900 | Intermedio $44.900 | Premium $69.900 |
|---|---|---|---|
| Servicios publicados | 3 | 10 | Sin límite |
| Fotos de portafolio | 6 | 20 | Sin límite |
| Posición en búsquedas | Normal | Media | Máxima |
| Insignia visible al cliente | — | Plus | Premium |
| Estadísticas detalladas de ingresos | — | Sí | Sí |
| Días de perfil destacado por activación | — | — | 7 |
| Primero en "Recomendados para ti" | — | — | Sí |
| Verificación prioritaria | — | — | Sí |
| Soporte prioritario por WhatsApp | — | — | Sí |

Para que el profesional vea el valor de su plan: tabla comparativa con la etiqueta "Más popular", contadores de uso ("2 de 3 servicios") con invitación a mejorar al llegar al límite, tarjeta "Lo que tu plan te ha traído" (visitas, solicitudes e ingresos del periodo) y avisos de renovación desde 5 días antes del vencimiento.

### Modo de pagos

- **Sin llaves de Wompi** y `PAYMENTS_MOCK=true` → la app muestra "Pago en modo pruebas" para simular aprobado/rechazado (también en el servidor de Render). Con llaves de Wompi siempre se usa la pasarela.
- **Con llaves sandbox**: llena `WOMPI_PUBLIC_KEY`, `WOMPI_PRIVATE_KEY`, `WOMPI_INTEGRITY_SECRET` y `WOMPI_EVENTS_SECRET` en `backend/.env` y configura en Wompi la URL de eventos `{PUBLIC_URL}/payments/webhooks/wompi` (el backend debe ser accesible desde internet, por ejemplo con un túnel).

## Configurar Wompi sandbox

1. Crea una cuenta de comercio en [comercios.wompi.co](https://comercios.wompi.co) (en modo pruebas no se mueve dinero real).
2. En el panel, sección **Desarrolladores**, copia las cuatro llaves de **pruebas** (`pub_test_…`, `prv_test_…`, el secreto de integridad `test_integrity_…` y el secreto de eventos `test_events_…`) y pégalas en `backend/.env`:

   ```
   WOMPI_ENV=sandbox
   WOMPI_PUBLIC_KEY=pub_test_...
   WOMPI_PRIVATE_KEY=prv_test_...
   WOMPI_INTEGRITY_SECRET=test_integrity_...
   WOMPI_EVENTS_SECRET=test_events_...
   PAYMENTS_MOCK=false
   ```

3. Para que Wompi avise los pagos, el backend debe ser accesible por https. En desarrollo usa un túnel, por ejemplo `cloudflared tunnel --url http://localhost:4000`, y pon esa URL en `PUBLIC_URL` y `PAYMENT_REDIRECT_URL` (`https://…/payments/return`).
4. En el panel de Wompi, en **URL de eventos**, pon `https://TU-TUNEL/payments/webhooks/wompi`.
5. Reinicia el backend. Prueba con las [tarjetas y datos de prueba de Wompi](https://docs.wompi.co/docs/colombia/datos-de-prueba-en-sandbox/) (por ejemplo, la tarjeta `4242 4242 4242 4242` se aprueba).

Las llaves privadas y secretas solo van en el backend, nunca en la app.

## Configurar Google Maps

1. En [Google Cloud Console](https://console.cloud.google.com) crea un proyecto y activa la facturación (Google da un crédito mensual gratuito).
2. Activa **Maps JavaScript API** (web) y **Maps SDK for Android** (y **Maps SDK for iOS** si se publicará en iPhone).
3. Crea una llave en **Credenciales** y restríngela: para web, por referentes HTTP (tu dominio y `localhost`); para Android, por nombre de paquete `co.netjob.netjob` y huella SHA-1.
4. Úsala al compilar con `--dart-define=MAPS_API_KEY=...` y en `app/android/local.properties`.

## Decisiones tomadas en esta entrega (revisar)

Los puntos de la sección 9 del documento siguen abiertos; implementé valores por defecto razonables que se pueden cambiar:

| Tema | Qué hace hoy el sistema | Dónde cambiarlo |
|---|---|---|
| Beneficios de planes | Básico: 3 servicios, 6 fotos. Intermedio: 10 / 20, prioridad media. Premium: ilimitado, prioridad máxima. | `prisma/seed.ts` o `PATCH /admin/plans/:id` |
| Solicitudes simultáneas | No se puede aceptar un servicio a menos de 2 h de otro aceptado o en proceso. | `BLOCK_HOURS` en `routes/requests.ts` |
| Visita de diagnóstico | La fija cada profesional (de $0 a $35.000), sin comisión NetJob. **No** se descuenta del valor final y **no** se reembolsa si el cliente cancela o rechaza la cotización. | Perfil del profesional; tope en *Admin → Configuración* |
| Cancelaciones | Se puede cancelar hasta antes de pagar el valor final. Pagado → reclamación que resuelve el administrador. | `routes/requests.ts`, `routes/claims.ts` |
| Fidelización y premios | Cada 3 servicios y calificación > 4,4 → tarifa del 1 %. Profesional ≥ 4,8 y activo → 10 % o 12 % de descuento. | Variables `LOYALTY_*` y `PRO_REWARD_*` en `config.ts` |
| Garantía | 30 días sobre la mano de obra desde que el servicio se finaliza. | `WARRANTY_DAYS` |
| Capacitación | 25 preguntas, se aprueba con 20, intentos ilimitados. | `TRAINING_PASS_SCORE`, `lib/training.ts` |
| Verificación obligatoria | Sí. Sin documentos aprobados por el administrador el profesional no aparece en búsquedas ni recibe solicitudes. Con `REQUIRE_VERIFICATION=false` pasa a ser opcional. | `config.ts`, `lib/profile.ts` |
| Inicio del servicio | El profesional solo puede iniciarlo después de que el valor final esté pagado. | `routes/requests.ts` |
| Valor del servicio | Precio publicado = "desde". El valor final lo cotiza el profesional tras el diagnóstico y puede corregirlo antes del pago. | `routes/requests.ts` |
| Radio de búsqueda | 12 km alrededor del cliente, igual para todos los profesionales. | `SEARCH_RADIUS_KM` |
| Perfil completo | Foto, título, descripción, especialidades, zona, horarios y mínimo 2 fotos de portafolio (se pueden subir antes de pagar el plan). | `lib/profile.ts`, `MIN_PORTFOLIO` |
| Verificación de profesionales | Cédula, selfie y certificado de antecedentes; aprueba el administrador. | `routes/trust.ts`, `PATCH /admin/verifications/:id` |
| Visibilidad sin suscripción | No aparece en búsquedas, no publica servicios ni acepta solicitudes. | `lib/subscriptions.ts` |

## Datos de prueba (50 profesionales)

```bash
cd backend
npm run demo:photos   # descarga las fotos (una vez; quedan en prisma/demo-photos, fuera de git)
npm run demo:pros     # crea los 50 profesionales (no duplica si se ejecuta de nuevo)
npm run demo:clients  # 20 clientes en Cartagena: demo-cliente-1 … demo-cliente-20@netjob.co (NetJob2026!)
npm run demo:cartagena  # pasa a Cartagena todos los profesionales que ya existan
```

## Producción de prueba: Supabase + Render + APK

1. **Supabase** (base de datos e imágenes): crea un proyecto. En *Project Settings → Database* copia las cadenas del **Transaction pooler** (puerto 6543) y del **Session pooler** (puerto 5432); en *Project Settings → API* copia la *Project URL* y la llave `service_role`.
2. **Tablas y datos**: llena `backend/.env.supabase` (no se sube a git) y desde `backend/`:
   ```bash
   npm run supabase:push   # crea las tablas en Supabase
   npm run supabase:seed   # categorías, planes, cuentas demo y los 50 profesionales (sube las fotos a Storage)
   ```
3. **Render** (API): sube el repositorio a GitHub y en Render elige *New → Blueprint* con este repositorio (`render.yaml`). Pega las cuatro variables de Supabase cuando las pida. La API queda en `https://netjob-api.onrender.com`.
4. **APK**: `flutter build apk --release --dart-define=API_URL=https://netjob-api.onrender.com --dart-define=MAPS_API_KEY=...`

En el plan gratuito de Render la API se duerme tras 15 minutos sin uso y la primera petición tarda unos 50 segundos. Para evitarlo durante la sustentación, programa un ping cada 10 minutos a `https://netjob-api.onrender.com/health` (por ejemplo con cron-job.org o UptimeRobot).

## Pendiente

- Notificaciones push (FCM) y envío real de correos (`lib/mailer.ts`, `lib/notify.ts`): hoy los avisos son dentro de la app y en tiempo real.
- Sitio web informativo.
- Pasarela real: los pagos funcionan en modo simulado (`PAYMENTS_MOCK=true`) o con llaves sandbox de Wompi. La dispersión real del dinero retenido y las devoluciones requieren un proveedor formal.
- Integraciones externas reales: proveedor de verificación (Truora/TusDatos) y aseguradora.
- Seguimiento en vivo con la app cerrada: la ubicación se envía mientras la pantalla de ruta está abierta.
- Almacenamiento de imágenes en la nube: listo con Supabase Storage (`SUPABASE_URL`); sin esas variables se usan `backend/uploads` y `backend/private-uploads`.
- Migraciones versionadas (`npm run db:migrate`) antes de pasar a producción, en lugar de `db push`.
