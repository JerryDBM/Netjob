-- Historial de prueba (ejecutar DESPUÉS de sherry-teto.sql):
--  * 5 servicios finalizados de Teto para Sherry, con cobro aprobado y dinero liberado,
--    repartidos en los últimos meses para que se vean las estadísticas.
--  * Cada uno con reseña de Sherry a Teto (5 positivas) y de Teto a Sherry (5 positivas).
--  * Teto pasa al plan Intermedio (las estadísticas detalladas son de ese plan en adelante).
--  * Jerry (primer usuario cuyo nombre empieza por "Jerry") con 2 solicitudes a Teto:
--    una aceptada (próxima cita) y una pendiente.
-- Pegar completo en Supabase → SQL Editor → Run. Volver a ejecutarlo no duplica.
DO $$
DECLARE
  teto_id text; sherry_id text; jerry_id text; prof_id text; req_id text; svc_id text;
  when_at timestamp; price int; fee int; i int;
  jobs text[][] := ARRAY[
    -- servicio, valor cobrado, días atrás, descripción, reseña de Sherry, reseña de Teto
    ARRAY['Limpieza profunda de apartamento', '120000', '140', 'Limpieza general antes de mudarme al apartamento.', 'Dejó el apartamento impecable, súper detallista. ¡La recomiendo!', 'Sherry fue muy amable y tenía todo listo para empezar. Excelente cliente.'],
    ARRAY['Arreglos menores del hogar', '105000', '105', 'Ajustar dos puertas que no cierran y colgar unas repisas.', 'Llegó puntual y arregló todo en menos de lo esperado.', 'Muy clara explicando lo que necesitaba. Pagó a tiempo.'],
    ARRAY['Organización de closets y espacios', '90000', '70', 'Organizar el closet principal y la cocina.', 'Mi closet nunca había estado tan ordenado. Muy creativa con el espacio.', 'Puntual, respetuosa y muy agradable. Ojalá todos los clientes fueran así.'],
    ARRAY['Limpieza profunda de apartamento', '130000', '35', 'Limpieza profunda después de una remodelación.', 'Otra vez excelente. Quitó todo el polvo de la obra sin dañar nada.', 'Siempre cumple lo acordado y tiene el espacio listo. 100 % recomendada.'],
    ARRAY['Arreglos menores del hogar', '70000', '9', 'Cambiar manijas de la cocina y arreglar un cajón.', 'Rápida, ordenada y con muy buena actitud. Volveré a llamarla.', 'Comunicación excelente por el chat y muy buena disposición.']
  ];
BEGIN
  SELECT id INTO teto_id FROM "User" WHERE email = 'teto123@gmail.com';
  SELECT id INTO sherry_id FROM "User" WHERE email = 'sherry123@gmail.com';
  SELECT id INTO prof_id FROM "ProfessionalProfile" WHERE "userId" = teto_id;
  IF prof_id IS NULL OR sherry_id IS NULL THEN
    RAISE EXCEPTION 'Primero ejecuta sherry-teto.sql';
  END IF;

  -- Plan Intermedio para Teto (estadísticas detalladas)
  UPDATE "Subscription" SET "planId" = (SELECT id FROM "SubscriptionPlan" WHERE code = 'INTERMEDIATE')
  WHERE "professionalId" = prof_id AND status = 'ACTIVE';

  IF NOT EXISTS (SELECT 1 FROM "ServiceRequest" WHERE "clientId" = sherry_id AND "professionalId" = prof_id AND status = 'COMPLETED') THEN
    FOR i IN 1 .. array_length(jobs, 1) LOOP
      SELECT id INTO svc_id FROM "Service" WHERE "professionalId" = prof_id AND title = jobs[i][1];
      price := jobs[i][2]::int;
      fee := round(price * 0.03);
      when_at := date_trunc('day', now()) - (jobs[i][3] || ' days')::interval + interval '15 hours';
      req_id := gen_random_uuid()::text;
      INSERT INTO "ServiceRequest" (id, "clientId", "professionalId", "serviceId", description, address, lat, lng, "scheduledAt", status,
        "diagnosticFee", "agreedPrice", "quoteNote", "quotedAt", "clientConfirmedAt", "proConfirmedAt", "warrantyUntil",
        "enRouteAt", "arrivedAt", "createdAt", "updatedAt")
      VALUES (req_id, sherry_id, prof_id, svc_id, jobs[i][4], 'Manga, Calle 27 #20-15, Cartagena', 10.412, -75.533, when_at, 'COMPLETED',
        0, price, 'Mano de obra y materiales básicos según lo revisado en la visita.', when_at + interval '30 minutes',
        when_at + interval '4 hours', when_at + interval '4 hours', when_at + interval '34 days',
        when_at - interval '40 minutes', when_at, when_at - interval '2 days', when_at + interval '4 hours');
      INSERT INTO "RequestStatusHistory" (id, "requestId", "fromStatus", "toStatus", "changedById", note, "createdAt") VALUES
        (gen_random_uuid()::text, req_id, NULL, 'PENDING', sherry_id, 'Solicitud creada', when_at - interval '2 days'),
        (gen_random_uuid()::text, req_id, 'PENDING', 'ACCEPTED', teto_id, NULL, when_at - interval '47 hours'),
        (gen_random_uuid()::text, req_id, 'ACCEPTED', 'IN_PROGRESS', teto_id, NULL, when_at + interval '1 hour'),
        (gen_random_uuid()::text, req_id, 'IN_PROGRESS', 'COMPLETED', teto_id, 'Ambas partes confirmaron', when_at + interval '4 hours');
      -- Cobro del servicio: aprobado y liberado a Teto
      INSERT INTO "Payment" (id, kind, reference, "payerId", "requestId", "serviceAmount", "commissionAmount", "totalAmount", status,
        "gatewayTransactionId", "paymentMethod", "payoutStatus", "payoutReleasedAt", "commissionRate", "createdAt", "updatedAt")
      VALUES (gen_random_uuid()::text, 'SERVICE', 'NJ-DEMO-TETO-' || i || '-' || substr(md5(req_id), 1, 8), sherry_id, req_id,
        price, fee, price + fee, 'APPROVED', 'demo-' || substr(md5(req_id), 1, 12), 'CARD', 'RELEASED', when_at + interval '4 hours', 0.03,
        when_at + interval '1 hour', when_at + interval '4 hours');
      INSERT INTO "Review" (id, "requestId", "authorId", "professionalId", rating, comment, "createdAt")
      VALUES (gen_random_uuid()::text, req_id, sherry_id, prof_id, 5, jobs[i][5], when_at + interval '6 hours');
      INSERT INTO "ClientReview" (id, "requestId", "authorId", "clientId", rating, comment, "createdAt")
      VALUES (gen_random_uuid()::text, req_id, teto_id, sherry_id, 5, jobs[i][6], when_at + interval '7 hours');
    END LOOP;
  END IF;

  -- Promedios de calificación
  UPDATE "ProfessionalProfile" SET
    "ratingAvg" = COALESCE((SELECT round(avg(rating)::numeric, 1) FROM "Review" WHERE "professionalId" = prof_id AND NOT hidden), 0),
    "ratingCount" = (SELECT count(*) FROM "Review" WHERE "professionalId" = prof_id AND NOT hidden)
  WHERE id = prof_id;
  UPDATE "User" SET
    "clientRatingAvg" = COALESCE((SELECT round(avg(rating)::numeric, 1) FROM "ClientReview" WHERE "clientId" = sherry_id AND NOT hidden), 0),
    "clientRatingCount" = (SELECT count(*) FROM "ClientReview" WHERE "clientId" = sherry_id AND NOT hidden)
  WHERE id = sherry_id;

  -- Solicitudes de Jerry a Teto
  SELECT id INTO jerry_id FROM "User" WHERE name ILIKE 'jerry%' AND id <> teto_id ORDER BY "createdAt" LIMIT 1;
  IF jerry_id IS NULL THEN
    RAISE NOTICE 'No se encontró un usuario llamado Jerry: se omiten sus solicitudes';
  ELSIF NOT EXISTS (SELECT 1 FROM "ServiceRequest" WHERE "clientId" = jerry_id AND "professionalId" = prof_id) THEN
    -- Aceptada: cita en 3 días
    SELECT id INTO svc_id FROM "Service" WHERE "professionalId" = prof_id AND title = 'Organización de closets y espacios';
    when_at := date_trunc('day', now()) + interval '3 days' + interval '19 hours'; -- 2:00 p. m. en Colombia
    req_id := gen_random_uuid()::text;
    INSERT INTO "ServiceRequest" (id, "clientId", "professionalId", "serviceId", description, address, lat, lng, "scheduledAt", status, "diagnosticFee", "createdAt", "updatedAt")
    VALUES (req_id, jerry_id, prof_id, svc_id, 'Quiero organizar el closet de mi cuarto y el escritorio.', 'Crespo, Carrera 3 #67-20, Cartagena', 10.443, -75.516, when_at, 'ACCEPTED', 0, now() - interval '1 day', now() - interval '20 hours');
    INSERT INTO "RequestStatusHistory" (id, "requestId", "fromStatus", "toStatus", "changedById", note, "createdAt") VALUES
      (gen_random_uuid()::text, req_id, NULL, 'PENDING', jerry_id, 'Solicitud creada', now() - interval '1 day'),
      (gen_random_uuid()::text, req_id, 'PENDING', 'ACCEPTED', teto_id, NULL, now() - interval '20 hours');
    INSERT INTO "Notification" (id, "userId", type, title, body, data)
    VALUES (gen_random_uuid()::text, jerry_id, 'REQUEST_ACCEPTED', 'Solicitud aceptada', 'Teto aceptó tu solicitud de "Organización de closets y espacios".', json_build_object('requestId', req_id));

    -- Pendiente: Teto debe confirmarla
    SELECT id INTO svc_id FROM "Service" WHERE "professionalId" = prof_id AND title = 'Arreglos menores del hogar';
    when_at := date_trunc('day', now()) + interval '5 days' + interval '14 hours'; -- 9:00 a. m. en Colombia
    req_id := gen_random_uuid()::text;
    INSERT INTO "ServiceRequest" (id, "clientId", "professionalId", "serviceId", description, address, lat, lng, "scheduledAt", status, "diagnosticFee", "updatedAt")
    VALUES (req_id, jerry_id, prof_id, svc_id, 'Instalar una repisa y arreglar la bisagra del baño.', 'Crespo, Carrera 3 #67-20, Cartagena', 10.443, -75.516, when_at, 'PENDING', 0, now());
    INSERT INTO "RequestStatusHistory" (id, "requestId", "toStatus", "changedById", note)
    VALUES (gen_random_uuid()::text, req_id, 'PENDING', jerry_id, 'Solicitud creada');
    INSERT INTO "Notification" (id, "userId", type, title, body, data)
    VALUES (gen_random_uuid()::text, teto_id, 'REQUEST_NEW', 'Nueva solicitud de servicio', 'Tienes una nueva solicitud para "Arreglos menores del hogar".', json_build_object('requestId', req_id));
  END IF;
END $$;
