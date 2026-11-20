-- Sherry (cliente) y Teto (profesional) en Cartagena, contraseña 12345678.
-- Pegar completo en Supabase → SQL Editor → Run. Volver a ejecutarlo no duplica.
DO $$
DECLARE
  pw text := '$2b$10$LjqHkMBtkviE1iCaXQ.Di.o/vXL.JiMbVXEJco1mG4qBVfqUyQs5.';
  teto_id text; sherry_id text; prof_id text; svc_id text; req_id text; when_at timestamp;
BEGIN
  INSERT INTO "User" (id, email, "passwordHash", name, phone, role, "avatarUrl", department, city, "updatedAt")
  VALUES (gen_random_uuid()::text, 'teto123@gmail.com', pw, 'Teto', '3001234567', 'PROFESSIONAL', 'https://raw.githubusercontent.com/JerryDBM/Netjob/claude/compassionate-franklin-1gzymp/backend/prisma/demo-users/teto.webp', 'Bolívar', 'Cartagena', now())
  ON CONFLICT (email) DO UPDATE SET name = 'Teto', role = 'PROFESSIONAL', "avatarUrl" = EXCLUDED."avatarUrl", city = 'Cartagena', department = 'Bolívar'
  RETURNING id INTO teto_id;

  INSERT INTO "User" (id, email, "passwordHash", name, phone, role, "avatarUrl", department, city, "updatedAt")
  VALUES (gen_random_uuid()::text, 'sherry123@gmail.com', pw, 'Sherry', '3007654321', 'CLIENT', 'https://raw.githubusercontent.com/JerryDBM/Netjob/claude/compassionate-franklin-1gzymp/backend/prisma/demo-users/sherry.jpg', 'Bolívar', 'Cartagena', now())
  ON CONFLICT (email) DO UPDATE SET name = 'Sherry', "avatarUrl" = EXCLUDED."avatarUrl", city = 'Cartagena', department = 'Bolívar'
  RETURNING id INTO sherry_id;

  SELECT id INTO prof_id FROM "ProfessionalProfile" WHERE "userId" = teto_id;
  IF prof_id IS NULL THEN
    prof_id := gen_random_uuid()::text;
    INSERT INTO "ProfessionalProfile" (id, "userId", headline, bio, "yearsExperience", city, "coverageArea", lat, lng, "diagnosticFee",
      verified, "verificationStatus", "verificationSubmittedAt", "verificationReviewedAt", "rulesAcceptedAt", "trainingPassedAt", "trainingScore", "trainingAttempts", "updatedAt")
    VALUES (prof_id, teto_id, 'Arreglos del hogar, limpieza y organización',
      'Soy Teto. Ayudo con arreglos pequeños, limpieza profunda y organización de espacios en Cartagena.',
      5, 'Cartagena', 'Manga, Bocagrande, Crespo y alrededores', 10.411, -75.534, 0,
      true, 'APPROVED', now() - interval '3 days', now() - interval '2 days', now() - interval '3 days', now() - interval '3 days', 24, 1, now());
    INSERT INTO "_CategoryToProfessionalProfile" ("A", "B")
      SELECT id, prof_id FROM "Category" WHERE slug IN ('otros', 'reparaciones');
    INSERT INTO "AvailabilitySlot" (id, "professionalId", "dayOfWeek", "startTime", "endTime")
      SELECT gen_random_uuid()::text, prof_id, d, '08:00', '18:00' FROM generate_series(1, 6) d;
    INSERT INTO "Subscription" (id, "professionalId", "planId", status, "startsAt", "endsAt")
      SELECT gen_random_uuid()::text, prof_id, id, 'ACTIVE', now() - interval '3 days', now() + interval '120 days' FROM "SubscriptionPlan" WHERE code = 'BASIC';
    INSERT INTO "Service" (id, "professionalId", "categoryId", title, description, price, "priceUnit", conditions, "coverageArea", "updatedAt") VALUES
      (gen_random_uuid()::text, prof_id, (SELECT id FROM "Category" WHERE slug = 'otros'), 'Limpieza profunda de apartamento',
        'Limpieza completa de cocina, baños, pisos y ventanas.', 120000, 'FIXED', 'El valor final se confirma después de la visita.', 'Cartagena', now()),
      (gen_random_uuid()::text, prof_id, (SELECT id FROM "Category" WHERE slug = 'reparaciones'), 'Arreglos menores del hogar',
        'Ajuste de puertas, cambio de manijas, colgar cuadros y repisas.', 35000, 'HOUR', 'El valor final se confirma después de la visita.', 'Cartagena', now()),
      (gen_random_uuid()::text, prof_id, (SELECT id FROM "Category" WHERE slug = 'otros'), 'Organización de closets y espacios',
        'Ordeno closets, cocinas y bodegas con sistema de cajas y etiquetas.', 90000, 'FIXED', 'El valor final se confirma después de la visita.', 'Cartagena', now());
  END IF;

  IF NOT EXISTS (SELECT 1 FROM "ServiceRequest" WHERE "clientId" = sherry_id AND "professionalId" = prof_id AND status = 'PENDING') THEN
    SELECT id INTO svc_id FROM "Service" WHERE "professionalId" = prof_id AND title = 'Limpieza profunda de apartamento';
    req_id := gen_random_uuid()::text;
    when_at := date_trunc('day', now()) + interval '2 days' + interval '15 hours'; -- 10:00 a. m. en Colombia
    INSERT INTO "ServiceRequest" (id, "clientId", "professionalId", "serviceId", description, address, lat, lng, "scheduledAt", status, "diagnosticFee", "updatedAt")
    VALUES (req_id, sherry_id, prof_id, svc_id, 'Necesito una limpieza profunda del apartamento antes de una visita familiar.',
      'Manga, Calle 27 #20-15, Cartagena', 10.412, -75.533, when_at, 'PENDING', 0, now());
    INSERT INTO "RequestStatusHistory" (id, "requestId", "toStatus", "changedById", note)
    VALUES (gen_random_uuid()::text, req_id, 'PENDING', sherry_id, 'Solicitud creada');
    INSERT INTO "Notification" (id, "userId", type, title, body, data)
    VALUES (gen_random_uuid()::text, teto_id, 'REQUEST_NEW', 'Nueva solicitud de servicio',
      'Tienes una nueva solicitud para "Limpieza profunda de apartamento".', json_build_object('requestId', req_id));
  END IF;
END $$;
