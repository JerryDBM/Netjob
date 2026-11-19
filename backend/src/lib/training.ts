/**
 * Capacitación inicial obligatoria del profesional: instructivos de lectura y un
 * cuestionario de 25 preguntas. Las respuestas correctas nunca salen del backend.
 */
export type Guide = { id: string; title: string; icon: string; summary: string; sections: { heading: string; points: string[] }[] };

export const guides: Guide[] = [
  {
    id: 'atencion',
    title: 'Atención al cliente',
    icon: 'support_agent',
    summary: 'Cómo tratar al cliente antes, durante y después del servicio.',
    sections: [
      {
        heading: 'Antes de la visita',
        points: [
          'Responde las solicitudes lo antes posible: un cliente que espera más de unas horas suele buscar a otro profesional.',
          'Usa el chat de NetJob para confirmar fecha, hora y dirección. Todo lo acordado debe quedar por escrito en el chat.',
          'Si no puedes atender, rechaza la solicitud con un motivo claro en lugar de dejarla sin respuesta.',
        ],
      },
      {
        heading: 'Durante el servicio',
        points: [
          'Saluda, preséntate con tu nombre y muestra tu perfil de NetJob si el cliente lo pide.',
          'Explica con palabras sencillas qué encontraste y qué vas a hacer antes de empezar.',
          'Trata al cliente y a su familia con respeto. No se permiten comentarios ofensivos, discriminatorios ni insinuaciones.',
          'Deja el lugar limpio y ordenado al terminar.',
        ],
      },
      {
        heading: 'Después del servicio',
        points: [
          'Muestra al cliente el trabajo terminado y resuelve sus dudas antes de pedirle que confirme.',
          'Una calificación baja se responde mejorando, no discutiendo. Si crees que una reseña es injusta, repórtala desde la app.',
        ],
      },
    ],
  },
  {
    id: 'acuerdos',
    title: 'Cumplimiento de acuerdos y cobros',
    icon: 'handshake',
    summary: 'Cotizaciones, pagos dentro de la app y qué pasa si no cumples.',
    sections: [
      {
        heading: 'Cotización y precio',
        points: [
          'El precio publicado es de referencia ("desde"). El valor final lo envías en la cotización después de la visita de diagnóstico.',
          'La cotización debe decir qué incluye: mano de obra, materiales y garantía.',
          'Puedes corregir la cotización mientras el cliente no haya pagado. Después de pagada, el valor no cambia.',
          'Está prohibido cobrar valores adicionales por fuera de la app o pedir pagos en efectivo.',
        ],
      },
      {
        heading: 'Pagos',
        points: [
          'El cliente paga la visita de diagnóstico y luego el valor cotizado dentro de NetJob.',
          'El valor del servicio queda retenido por NetJob y se libera cuando tú y el cliente confirman que el trabajo terminó.',
          'La tarifa de NetJob la paga el cliente: tú recibes el valor completo que cotizaste.',
        ],
      },
      {
        heading: 'Puntualidad e incumplimientos',
        points: [
          'Llega a la hora acordada. Si vas a tardar, avisa por el chat antes de la hora de la cita.',
          'Marca "Voy en camino" cuando salgas: el cliente podrá ver tu ubicación hasta que llegues.',
          'No presentarte sin avisar, abandonar un trabajo o cobrar por fuera puede llevar a la suspensión de tu perfil.',
        ],
      },
    ],
  },
  {
    id: 'seguridad',
    title: 'Protocolos de seguridad',
    icon: 'health_and_safety',
    summary: 'Cuida tu integridad, la del cliente y la de su hogar.',
    sections: [
      {
        heading: 'Tu seguridad',
        points: [
          'Usa los elementos de protección de tu oficio: guantes, gafas, calzado adecuado y, en altura, arnés.',
          'En trabajos eléctricos corta la energía desde el tablero y verifica la ausencia de tensión antes de tocar cables.',
          'Si el lugar es inseguro o el trabajo supera tu capacidad, no lo hagas: explícalo al cliente y repórtalo a soporte.',
        ],
      },
      {
        heading: 'Seguridad del cliente y su hogar',
        points: [
          'Entra solo a las áreas necesarias para el trabajo y siempre con autorización del cliente.',
          'No recibas ni pidas llaves, claves o datos personales que no necesites.',
          'Si causas un daño, infórmalo de inmediato al cliente y repórtalo en la app: NetJob gestiona el caso con la aseguradora aliada.',
          'No trabajes bajo los efectos del alcohol u otras sustancias.',
        ],
      },
      {
        heading: 'Emergencias',
        points: [
          'Ante una emergencia llama primero a la línea 123.',
          'Después repórtalo a soporte de NetJob por WhatsApp para dejar constancia.',
        ],
      },
    ],
  },
  {
    id: 'reglas',
    title: 'Reglas y condiciones de NetJob',
    icon: 'gavel',
    summary: 'Lo que aceptas al ofrecer tus servicios en la plataforma.',
    sections: [
      {
        heading: 'Tu cuenta',
        points: [
          'La cuenta es personal: no puedes prestarla ni enviar a otra persona en tu lugar.',
          'La información de tu perfil, tus documentos y tu portafolio deben ser reales y tuyos.',
          'Debes mantener una suscripción activa para aparecer en las búsquedas y aceptar solicitudes.',
        ],
      },
      {
        heading: 'Calidad y seguimiento',
        points: [
          'Los clientes te califican al terminar y tú calificas a los clientes.',
          'Si tu calificación promedio baja de 3,5 con al menos tres reseñas, tu perfil entra en revisión y mejora.',
          'Las faltas graves o repetidas (cobros por fuera, maltrato, abandono del trabajo) pueden suspender tu perfil de forma temporal o definitiva.',
          'Los clientes pasan por un proceso equivalente: también pueden ser revisados y suspendidos.',
        ],
      },
      {
        heading: 'Garantía y reclamaciones',
        points: [
          'La mano de obra tiene una garantía de 30 días: si el arreglo falla en ese tiempo, debes volver a revisarlo.',
          'Cualquier desacuerdo se tramita con una reclamación en la app; el equipo de NetJob revisa el chat, las fotos y el historial.',
          'Mientras haya una reclamación abierta, el dinero del servicio sigue retenido.',
        ],
      },
      {
        heading: 'Beneficios por buen desempeño',
        points: [
          'Con calificación de 4,8 o más y actividad constante obtienes descuento en tu siguiente suscripción y un potenciador de recomendación.',
          'Invitar a otros profesionales con tu código también te da un potenciador.',
        ],
      },
    ],
  },
];

type Question = { q: string; options: string[]; answer: number };

const questions: Question[] = [
  { q: 'Un cliente te envía una solicitud y no puedes atenderla. ¿Qué haces?', options: ['La dejas sin responder', 'La rechazas con un motivo claro', 'La aceptas y luego no vas'], answer: 1 },
  { q: '¿Dónde debe quedar lo que acuerdas con el cliente (fecha, hora, detalles)?', options: ['En el chat de NetJob', 'Solo de palabra', 'En una llamada'], answer: 0 },
  { q: 'Al llegar al domicilio del cliente, lo primero es:', options: ['Empezar a trabajar de una vez', 'Saludar, presentarte y explicar qué vas a revisar', 'Pedir el pago en efectivo'], answer: 1 },
  { q: 'El precio que publicas en tus servicios es:', options: ['El valor final y no se puede cambiar', 'Un precio de referencia ("desde")', 'El valor de la visita'], answer: 1 },
  { q: '¿Cuándo envías la cotización con el valor final?', options: ['Antes de aceptar la solicitud', 'Después de la visita de diagnóstico', 'Cuando termines el trabajo'], answer: 1 },
  { q: 'Una buena cotización debe indicar:', options: ['Solo el precio', 'Qué incluye: mano de obra, materiales y garantía', 'Tu número de cuenta'], answer: 1 },
  { q: 'El cliente ya pagó la cotización y descubres un gasto extra. ¿Qué haces?', options: ['Le cobras la diferencia en efectivo', 'Se lo explicas y lo tramitan por la app o con soporte', 'Dejas el trabajo a medias'], answer: 1 },
  { q: '¿Se puede cobrar al cliente por fuera de la app?', options: ['Sí, si el cliente acepta', 'No, está prohibido', 'Solo los materiales'], answer: 1 },
  { q: '¿Quién paga la tarifa de NetJob en un servicio?', options: ['El profesional', 'El cliente', 'Se reparte entre los dos'], answer: 1 },
  { q: '¿Cuándo se libera a tu favor el dinero del servicio?', options: ['Apenas el cliente paga', 'Cuando tú y el cliente confirman que el trabajo terminó', 'A fin de mes'], answer: 1 },
  { q: 'Vas a llegar tarde a la cita. Lo correcto es:', options: ['Avisar por el chat antes de la hora acordada', 'Llegar cuando puedas sin avisar', 'Cancelar sin explicación'], answer: 0 },
  { q: '¿Para qué sirve marcar "Voy en camino"?', options: ['Para cobrar más', 'Para avisar al cliente y que vea tu ubicación hasta que llegues', 'Para finalizar el servicio'], answer: 1 },
  { q: '¿Hasta cuándo ve el cliente tu ubicación?', options: ['Todo el día', 'Solo mientras vas en camino, hasta que llegas', 'Siempre que tengas la app abierta'], answer: 1 },
  { q: 'Antes de intervenir una instalación eléctrica debes:', options: ['Trabajar rápido con la energía conectada', 'Cortar la energía y verificar que no haya tensión', 'Mojar la zona'], answer: 1 },
  { q: 'El trabajo es más peligroso de lo que puedes manejar. ¿Qué haces?', options: ['Lo intentas igual', 'No lo haces, se lo explicas al cliente y lo reportas a soporte', 'Mandas a un conocido'], answer: 1 },
  { q: 'Dentro de la casa del cliente puedes entrar a:', options: ['Cualquier habitación', 'Solo las áreas necesarias y con autorización', 'Donde no te vean'], answer: 1 },
  { q: 'Rompiste algo en el domicilio por accidente. Lo correcto es:', options: ['No decir nada', 'Informar al cliente y reportarlo en la app', 'Culpar al cliente'], answer: 1 },
  { q: 'Ante una emergencia grave durante un servicio, primero:', options: ['Escribes al chat', 'Llamas a la línea 123', 'Terminas el trabajo'], answer: 1 },
  { q: '¿Puedes enviar a otra persona a hacer el trabajo con tu cuenta?', options: ['Sí, si es de confianza', 'No, la cuenta es personal', 'Solo los fines de semana'], answer: 1 },
  { q: 'Las fotos de tu portafolio deben ser:', options: ['Tomadas de internet', 'De trabajos reales hechos por ti', 'De otros profesionales'], answer: 1 },
  { q: 'Tu perfil entra en revisión cuando tu calificación promedio:', options: ['Baja de 3,5 con al menos tres reseñas', 'Baja de 4,9', 'Nunca'], answer: 0 },
  { q: 'Recibes una reseña que consideras injusta. ¿Qué haces?', options: ['Insultas al cliente por el chat', 'La reportas desde la app para que la revisen', 'Creas otra cuenta'], answer: 1 },
  { q: '¿Cuánto dura la garantía de la mano de obra?', options: ['No hay garantía', '30 días', '1 año'], answer: 1 },
  { q: 'Mientras hay una reclamación abierta sobre un servicio, el dinero:', options: ['Se libera de inmediato', 'Sigue retenido hasta que se resuelva', 'Se pierde'], answer: 1 },
  { q: '¿Qué obtienes con calificación de 4,8 o más y actividad constante?', options: ['Nada', 'Descuento en tu siguiente suscripción y un potenciador de recomendación', 'Una multa'], answer: 1 },
];

/** Preguntas para la app, sin la respuesta correcta. */
export const publicQuestions = () => questions.map((x, i) => ({ id: i, q: x.q, options: x.options }));

export const totalQuestions = questions.length;

/** Califica las respuestas (índice de opción por pregunta). */
export function gradeQuiz(answers: number[]) {
  const wrong: number[] = [];
  questions.forEach((x, i) => {
    if (answers[i] !== x.answer) wrong.push(i);
  });
  return { score: questions.length - wrong.length, total: questions.length, wrong };
}
