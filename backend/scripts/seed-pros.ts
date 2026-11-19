/**
 * Datos de prueba: 50 profesionales completos en Cartagena, repartidos por barrios
 * (perfil detallado, servicios, portafolio con fotos, horarios, plan activo, verificación,
 * capacitación y reseñas reales de servicios finalizados).
 *
 *   npm run demo:photos   # primero: descarga las fotos (una sola vez)
 *   npm run demo:pros
 *
 * Las imágenes se suben a Supabase Storage si está configurado (o a uploads/ en local).
 * Contraseña de todas las cuentas: NetJob2026!  Volver a ejecutarlo no duplica cuentas.
 */
import fs from 'node:fs';
import path from 'node:path';
import bcrypt from 'bcryptjs';
import type { PriceUnit } from '@prisma/client';
import { prisma } from '../src/db.js';
import { storeBuffer, cloudStorage, ensureBuckets } from '../src/lib/upload.js';
import { BARRIOS, CARTAGENA, placeFor } from './cartagena.js';
import { CARMEN, CARMEN_BARRIOS, carmenPlaceFor } from './carmen.js';

const PHOTOS = path.resolve('prisma/demo-photos');
if (!fs.existsSync(PHOTOS)) {
  console.error('Faltan las fotos. Ejecuta primero: npm run demo:photos');
  process.exit(1);
}
const credits: Record<string, { title: string; creator: string | null; license: string }> = JSON.parse(
  fs.readFileSync(path.join(PHOTOS, 'credits.json'), 'utf8'),
);

// ---------------------------------------------------------------- Ciudades

type City = { name: string; dept: string; lat: number; lng: number; areas: string[] };
const CITIES: Record<string, City> = {
  ctg: { name: 'Cartagena', dept: 'Bolívar', lat: 10.391, lng: -75.4794, areas: ['Manga', 'Bocagrande', 'Crespo', 'El Bosque', 'Pie de la Popa', 'Los Alpes', 'Castillogrande', 'San Fernando', 'Torices', 'Olaya Herrera'] },
  carmen: { name: 'El Carmen de Bolívar', dept: 'Bolívar', lat: 9.7174, lng: -75.1202, areas: ['Centro', 'Barrio Nuevo', 'El Silencio', 'Las Palmas', 'San José', 'Villa Ana', 'Caracolí'] },
  baq: { name: 'Barranquilla', dept: 'Atlántico', lat: 10.9685, lng: -74.7813, areas: ['El Prado', 'Riomar', 'Alto Prado', 'Boston', 'Las Delicias', 'Ciudad Jardín', 'Villa Country', 'El Recreo'] },
  bog: { name: 'Bogotá', dept: 'Cundinamarca', lat: 4.6486, lng: -74.082, areas: ['Chapinero', 'Teusaquillo', 'Usaquén', 'Suba', 'Kennedy', 'Engativá', 'Cedritos', 'Fontibón'] },
  med: { name: 'Medellín', dept: 'Antioquia', lat: 6.2442, lng: -75.5812, areas: ['Laureles', 'El Poblado', 'Belén', 'Envigado', 'Robledo', 'La América', 'Estadio'] },
  sinc: { name: 'Sincelejo', dept: 'Sucre', lat: 9.3047, lng: -75.3978, areas: ['Centro', 'Majagual', 'La Ford', 'Venecia', 'Boston', 'Las Margaritas'] },
};

// ---------------------------------------------------------------- Oficios

type Svc = { title: string; description: string; conditions: string; price: number; unit: PriceUnit };
type Trade = {
  headlines: string[];
  specialties: string[];
  process: string[];
  services: Svc[];
  works: { title: string; description: string }[];
  reviews: string[];
};

const T: Record<string, Trade> = {
  plomeria: {
    headlines: ['Plomero residencial y comercial', 'Técnico en redes hidráulicas y sanitarias', 'Plomería, destapes y griferías', 'Plomero con atención de urgencias'],
    specialties: [
      'Reparo fugas visibles y ocultas en tuberías de PVC, CPVC y cobre, cambio empaques y válvulas, y dejo los sanitarios funcionando sin goteos.',
      'Destapo lavaplatos, sifones, sanitarios y cajas de inspección con sonda eléctrica, sin romper pisos cuando no es necesario.',
      'Instalo y cambio griferías, lavamanos, sanitarios, duchas y calentadores de paso a gas o eléctricos.',
      'Hago mantenimiento a tanques elevados y bombas de presión, y reviso por qué baja la presión del agua en la casa.',
    ],
    process: [
      'Antes de cotizar hago una prueba de presión para ubicar exactamente la fuga y le explico al cliente qué encontré, con fotos.',
      'Llevo mis propias herramientas y repuestos básicos; si se necesita algo especial, le paso al cliente la lista con precios para que decida.',
      'Al terminar pruebo todo con el cliente presente y dejo el área limpia y seca.',
    ],
    services: [
      { title: 'Reparación de fugas de agua', description: 'Detección y reparación de fugas en tuberías, llaves de paso, sanitarios y lavamanos. Incluye prueba de presión para ubicar fugas ocultas y cambio de empaques o tramos dañados.', conditions: 'Precio desde, sin materiales. Si la fuga está dentro de la pared, el resane se cotiza aparte.', price: 70_000, unit: 'FIXED' },
      { title: 'Destape de cañerías y sanitarios', description: 'Destape de lavaplatos, lavamanos, duchas, sanitarios y cajas de inspección con sonda eléctrica. Se revisa la causa del taponamiento para evitar que se repita.', conditions: 'No incluye cambio de tubería si está rota. Garantía de 15 días en el mismo punto.', price: 60_000, unit: 'FIXED' },
      { title: 'Instalación de grifería y lavamanos', description: 'Instalación o cambio de grifería de cocina y baño, lavamanos, mezcladores y duchas. Se sellan conexiones y se revisa que no haya goteo.', conditions: 'El cliente compra la grifería; puedo recomendar marcas según el presupuesto.', price: 55_000, unit: 'FIXED' },
      { title: 'Instalación de calentador de paso', description: 'Instalación de calentador a gas o eléctrico con sus conexiones de agua, regulador y prueba de funcionamiento. Se revisa ventilación según la norma.', conditions: 'La conexión a la red de gas debe estar certificada por la empresa prestadora.', price: 150_000, unit: 'FIXED' },
      { title: 'Mantenimiento de tanque y bomba', description: 'Lavado y desinfección de tanque elevado o subterráneo, revisión de flotador y de la bomba de presión, cambio de cheque si es necesario.', conditions: 'Tanques de hasta 2.000 litros. Para tanques más grandes se cotiza en la visita.', price: 120_000, unit: 'FIXED' },
    ],
    works: [
      { title: 'Cambio de tubería de cocina', description: 'Se reemplazó tubería galvanizada corroída por PVC presión. Quedó sin fugas y con mejor presión en el lavaplatos.' },
      { title: 'Baño con grifería nueva', description: 'Instalación de lavamanos, mezclador y ducha teléfono en un baño social.' },
      { title: 'Reparación de fuga oculta', description: 'Fuga dentro de muro detectada con prueba de presión; se abrió solo lo necesario y se resanó.' },
      { title: 'Calentador instalado', description: 'Calentador de paso a gas con regulador nuevo y prueba de hermeticidad.' },
      { title: 'Destape de caja de inspección', description: 'Destape con sonda eléctrica y limpieza de la caja; se dejó la rejilla nueva.' },
      { title: 'Mantenimiento de bomba de presión', description: 'Cambio de cheque y presostato; la bomba dejó de prender sola en la noche.' },
    ],
    reviews: [
      'Encontró la fuga en minutos y me explicó todo antes de cobrar. Muy recomendado.',
      'Destapó el lavaplatos sin romper nada y dejó todo limpio.',
      'Llegó a la hora, trajo sus repuestos y el baño quedó perfecto.',
      'Muy honesto: me dijo que no era necesario cambiar toda la tubería.',
      'Instaló el calentador y nos explicó cómo usarlo. Excelente.',
    ],
  },
  electricidad: {
    headlines: ['Electricista residencial certificado', 'Técnico electricista con matrícula CONTE', 'Instalaciones eléctricas y mantenimiento', 'Electricista para hogares y locales'],
    specialties: [
      'Reviso cortos, breakers que se disparan y tomas que no funcionan, y dejo la instalación según el RETIE.',
      'Instalo lámparas, ventiladores de techo, tomas, interruptores y circuitos nuevos para aires acondicionados o estufas eléctricas.',
      'Cambio tableros de breakers, organizo circuitos y marco cada uno para que el cliente sepa qué apaga cada breaker.',
      'Hago acometidas, puesta a tierra y revisión completa de la instalación antes de una mudanza o compra de vivienda.',
    ],
    process: [
      'Siempre trabajo con el circuito desenergizado y mido con multímetro antes y después de cada arreglo.',
      'Le explico al cliente qué causó la falla y qué hacer para que no se repita.',
      'Uso materiales certificados y entrego factura de compra de los repuestos cuando el cliente la necesita.',
    ],
    services: [
      { title: 'Revisión de cortos y breakers', description: 'Diagnóstico de cortos, breakers que se disparan, tomas sin corriente y bajones de luz. Se mide la instalación y se corrige la falla.', conditions: 'Si se necesita cablear de nuevo un circuito, se cotiza por punto.', price: 60_000, unit: 'VISIT' },
      { title: 'Instalación de ventilador de techo', description: 'Instalación de ventilador de techo con soporte reforzado, conexión al interruptor o control remoto y balanceo para que no vibre.', conditions: 'Hasta 3 metros de altura. Si no hay salida eléctrica en el techo, se cotiza el punto.', price: 70_000, unit: 'FIXED' },
      { title: 'Punto eléctrico nuevo (toma o interruptor)', description: 'Instalación de toma, interruptor o salida de lámpara nueva con tubería a la vista o empotrada, incluida la conexión al tablero.', conditions: 'Precio por punto; el resane de pared empotrada se cotiza aparte.', price: 55_000, unit: 'FIXED' },
      { title: 'Cambio de tablero de breakers', description: 'Cambio de tablero viejo por uno nuevo, organización y marcación de circuitos, revisión de puesta a tierra.', conditions: 'Tablero de hasta 12 circuitos. El cliente puede comprar el tablero o lo consigo con factura.', price: 250_000, unit: 'FIXED' },
      { title: 'Circuito para aire acondicionado', description: 'Circuito independiente con breaker y cable del calibre correcto para aire acondicionado o estufa eléctrica.', conditions: 'Hasta 15 metros de cable desde el tablero.', price: 180_000, unit: 'FIXED' },
    ],
    works: [
      { title: 'Tablero organizado y marcado', description: 'Cambio de tablero y marcación de todos los circuitos de un apartamento.' },
      { title: 'Ventiladores de techo', description: 'Instalación de tres ventiladores con control remoto en una casa de dos pisos.' },
      { title: 'Iluminación LED en sala', description: 'Cambio de lámparas por paneles LED y nuevos interruptores.' },
      { title: 'Circuito para minisplit', description: 'Circuito independiente de 220 V para un aire de 12.000 BTU.' },
      { title: 'Revisión antes de mudanza', description: 'Revisión completa de la instalación y corrección de tres tomas sin polo a tierra.' },
      { title: 'Local comercial', description: 'Cableado y tomas nuevas para una tienda de barrio.' },
    ],
    reviews: [
      'Encontró el corto que nadie había podido arreglar. Muy cumplido.',
      'Instaló los ventiladores rápido y no vibran nada.',
      'Explica todo con paciencia y trabaja con mucha seguridad.',
      'Dejó el tablero marcado, ahora sé qué es cada breaker.',
      'Puntual y con buen precio. Lo vuelvo a llamar.',
    ],
  },
  carpinteria: {
    headlines: ['Carpintero ebanista', 'Muebles a la medida y reparaciones en madera', 'Carpintería fina y cocinas integrales', 'Carpintero con taller propio'],
    specialties: [
      'Fabrico closets, cocinas integrales, centros de entretenimiento y muebles a la medida en madera o MDF.',
      'Reparo puertas que no cierran, cajones descolgados, bisagras y muebles con comején.',
      'Restauro muebles antiguos: lijado, resane, tinte y laca para que queden como nuevos.',
      'Instalo puertas, marcos y guardaescobas, y ajusto puertas que rozan con el piso.',
    ],
    process: [
      'Tomo medidas en la primera visita, le muestro al cliente un diseño sencillo y le doy dos opciones de material con precios.',
      'Los muebles se fabrican en mi taller y se instalan en una sola visita para no ensuciar la casa.',
      'Doy garantía de seis meses en herrajes y ajustes de los muebles que fabrico.',
    ],
    services: [
      { title: 'Reparación de muebles y puertas', description: 'Ajuste de puertas que rozan o no cierran, cambio de bisagras y correderas, reparación de cajones y sillas.', conditions: 'Precio por hora; los herrajes se cobran aparte.', price: 35_000, unit: 'HOUR' },
      { title: 'Closet a la medida', description: 'Diseño, fabricación e instalación de closets en MDF o madera con entrepaños, cajones y tubo para colgar.', conditions: 'Precio desde por metro lineal en MDF de 15 mm. Entrega de 10 a 15 días.', price: 450_000, unit: 'FIXED' },
      { title: 'Cocina integral', description: 'Muebles superiores e inferiores a la medida, con herrajes de cierre lento y mesón a elección del cliente.', conditions: 'Precio desde por metro lineal, sin mesón. Diseño incluido.', price: 900_000, unit: 'FIXED' },
      { title: 'Restauración de muebles', description: 'Lijado, resane, tratamiento contra comején, tinte y laca de muebles de madera.', conditions: 'Se cotiza según tamaño y estado del mueble.', price: 120_000, unit: 'FIXED' },
      { title: 'Instalación de puertas', description: 'Instalación de puerta con marco, chapa y bisagras, nivelada y ajustada.', conditions: 'El cliente compra la puerta y la chapa.', price: 130_000, unit: 'FIXED' },
    ],
    works: [
      { title: 'Closet de habitación principal', description: 'Closet de piso a techo en MDF blanco con cajones de cierre lento.' },
      { title: 'Cocina integral en L', description: 'Muebles superiores e inferiores con mesón en granito.' },
      { title: 'Restauración de mecedora', description: 'Mecedora antigua lijada, resanada y lacada.' },
      { title: 'Puerta en cedro', description: 'Fabricación e instalación de puerta principal en cedro.' },
      { title: 'Centro de entretenimiento', description: 'Mueble flotante para televisor con repisas y luz LED.' },
      { title: 'Biblioteca a la medida', description: 'Biblioteca empotrada con puertas inferiores.' },
    ],
    reviews: [
      'El closet quedó hermoso y entregó en la fecha prometida.',
      'Arregló todas las puertas de la casa en una tarde.',
      'Muy detallista con los acabados. Recomendadísimo.',
      'La cocina quedó tal cual el diseño que nos mostró.',
      'Restauró el comedor de mi abuela, quedó como nuevo.',
    ],
  },
  pintura: {
    headlines: ['Pintor y estucador', 'Pintura de interiores y fachadas', 'Acabados, estuco y pintura', 'Pintor profesional con equipo de trabajo'],
    specialties: [
      'Pinto interiores y fachadas con preparación completa: raspado, resane, estuco y dos manos de pintura.',
      'Trato humedades y salitre antes de pintar para que la pintura no se vuelva a soplar.',
      'Aplico estuco veneciano, texturas y pintura en techos y cielos rasos de drywall.',
      'Pinto rejas, puertas metálicas y portones con anticorrosivo y esmalte.',
    ],
    process: [
      'Protejo pisos y muebles con plástico y cinta antes de empezar, y al final entrego todo limpio.',
      'Le ayudo al cliente a calcular la pintura que necesita para que no compre de más.',
      'Trabajo con pinturas tipo 1 o la que el cliente prefiera, y respeto los tiempos de secado.',
    ],
    services: [
      { title: 'Pintura de habitación', description: 'Pintura de habitación estándar (paredes y techo) con resanes menores y dos manos de pintura.', conditions: 'Habitación de hasta 12 m². Pintura a cargo del cliente.', price: 180_000, unit: 'FIXED' },
      { title: 'Pintura de fachada', description: 'Lavado, raspado, resane y pintura de fachada con pintura para exteriores.', conditions: 'Precio desde por metro cuadrado. Andamio incluido hasta segundo piso.', price: 12_000, unit: 'FIXED' },
      { title: 'Tratamiento de humedades', description: 'Raspado, aplicación de impermeabilizante y sellador, resane y pintura de muros con humedad o salitre.', conditions: 'Se revisa primero el origen de la humedad; si es una fuga, se recomienda arreglarla antes.', price: 90_000, unit: 'VISIT' },
      { title: 'Estuco y resanes', description: 'Estucado de paredes, arreglo de grietas y fisuras, y lijado para dejar la superficie lista para pintar.', conditions: 'Precio por metro cuadrado.', price: 15_000, unit: 'FIXED' },
      { title: 'Pintura de rejas y puertas metálicas', description: 'Lijado, anticorrosivo y esmalte en rejas, portones y puertas metálicas.', conditions: 'Se cotiza según tamaño.', price: 80_000, unit: 'FIXED' },
    ],
    works: [
      { title: 'Sala y comedor', description: 'Estuco, resanes y pintura en tono arena.' },
      { title: 'Fachada de dos pisos', description: 'Lavado, resane y pintura exterior.' },
      { title: 'Habitación infantil', description: 'Pintura en dos tonos con franja decorativa.' },
      { title: 'Muro con humedad', description: 'Tratamiento de salitre e impermeabilización antes de pintar.' },
      { title: 'Reja y portón', description: 'Anticorrosivo y esmalte negro mate.' },
      { title: 'Local comercial', description: 'Pintura de local en un fin de semana para no cerrar el negocio.' },
    ],
    reviews: [
      'Dejó todo limpio, ni una gota en el piso.',
      'La humedad no ha vuelto a salir. Excelente trabajo.',
      'Rápido, ordenado y con muy buenos acabados.',
      'Nos ayudó a escoger los colores, quedó lindo.',
      'Cumplió con el tiempo y el precio acordado.',
    ],
  },
  cerrajeria: {
    headlines: ['Cerrajero 24 horas', 'Cerrajería residencial y automotriz', 'Cerraduras de seguridad y aperturas', 'Cerrajero a domicilio'],
    specialties: [
      'Abro puertas de casas y apartamentos sin dañar la cerradura cuando el cliente queda por fuera.',
      'Cambio guardas y cilindros después de una mudanza o de perder las llaves.',
      'Instalo cerraduras de seguridad, cerrojos digitales y barras antipánico.',
      'Hago copias de llaves y reparo chapas de portones y puertas metálicas.',
    ],
    process: [
      'Pido al cliente que demuestre que vive en el lugar antes de abrir una puerta.',
      'Le explico las opciones de seguridad según su presupuesto, sin vender lo que no necesita.',
      'Llego rápido a las urgencias y cobro lo que se acordó en la app.',
    ],
    services: [
      { title: 'Apertura de puertas', description: 'Apertura de puertas de casas, apartamentos y oficinas sin daños, a domicilio.', conditions: 'Se pide documento que demuestre que vive en el lugar. Recargo nocturno después de las 9 p. m.', price: 60_000, unit: 'FIXED' },
      { title: 'Cambio de guarda o cilindro', description: 'Cambio de guarda o cilindro de cerradura con tres llaves nuevas.', conditions: 'Incluye guarda estándar; las de alta seguridad se cotizan.', price: 70_000, unit: 'FIXED' },
      { title: 'Instalación de cerradura de seguridad', description: 'Instalación de cerradura de seguridad, cerrojo o cerradura digital con ajuste de la puerta.', conditions: 'El cliente puede comprar la cerradura o la consigo con factura.', price: 90_000, unit: 'FIXED' },
      { title: 'Reparación de chapas de portón', description: 'Reparación o cambio de chapas de portones, rejas y puertas metálicas.', conditions: 'Se cotiza según el tipo de chapa.', price: 65_000, unit: 'FIXED' },
    ],
    works: [
      { title: 'Cerradura digital', description: 'Instalación de cerradura con clave y tarjeta en apartamento.' },
      { title: 'Cambio de guardas', description: 'Cambio de guardas de todas las puertas tras una mudanza.' },
      { title: 'Apertura sin daños', description: 'Apertura de puerta principal sin dañar la chapa.' },
      { title: 'Cerrojo de seguridad', description: 'Cerrojo adicional en puerta de madera.' },
      { title: 'Chapa de portón', description: 'Cambio de chapa eléctrica de portón de garaje.' },
    ],
    reviews: [
      'Llegó en 20 minutos y abrió sin dañar nada.',
      'Me cambió las guardas el mismo día. Muy confiable.',
      'La cerradura digital quedó perfecta y me enseñó a configurarla.',
      'Honesto con el precio, no cobró de más por ser de noche.',
    ],
  },
  reparaciones: {
    headlines: ['Maestro de obra y reparaciones locativas', 'Mantenimiento general del hogar', 'Reparaciones, enchapes y drywall', 'Todero de confianza'],
    specialties: [
      'Hago enchapes de pisos y baños, cambio baldosas sueltas y emboquillo.',
      'Instalo y reparo drywall: divisiones, cielos rasos y huecos en paredes.',
      'Reparo goteras, impermeabilizo terrazas y cambio tejas.',
      'Hago pequeñas remodelaciones: baños, mesones, muros y repellos.',
    ],
    process: [
      'Visito, mido y entrego la cotización por escrito con materiales y mano de obra separados.',
      'Trabajo con un ayudante para terminar más rápido y en los horarios que el cliente prefiera.',
      'Recojo los escombros al final de cada día.',
    ],
    services: [
      { title: 'Enchape de pisos y baños', description: 'Instalación de cerámica o porcelanato en pisos, paredes de baño y cocina, con nivelación y emboquillado.', conditions: 'Precio por metro cuadrado, sin material.', price: 35_000, unit: 'FIXED' },
      { title: 'Reparación de goteras', description: 'Revisión del techo, cambio de tejas rotas, sellado de uniones e impermeabilización del punto afectado.', conditions: 'Techos de hasta dos pisos.', price: 120_000, unit: 'VISIT' },
      { title: 'Drywall y cielo raso', description: 'Instalación de divisiones y cielos rasos en drywall, o reparación de huecos y fisuras.', conditions: 'Precio por metro cuadrado con masilla y pintura base.', price: 45_000, unit: 'FIXED' },
      { title: 'Mantenimiento general', description: 'Arreglos varios del hogar: repisas, cortineros, cuadros, ajustes y pequeños resanes.', conditions: 'Precio por hora, mínimo dos horas.', price: 30_000, unit: 'HOUR' },
      { title: 'Impermeabilización de terraza', description: 'Limpieza, sellado de fisuras y aplicación de manto o impermeabilizante líquido.', conditions: 'Precio por metro cuadrado.', price: 28_000, unit: 'FIXED' },
    ],
    works: [
      { title: 'Baño remodelado', description: 'Enchape de piso y paredes con porcelanato y nueva división de ducha.' },
      { title: 'Cielo raso en drywall', description: 'Cielo raso con luces empotradas en sala.' },
      { title: 'Terraza impermeabilizada', description: 'Manto asfáltico y pintura reflectiva.' },
      { title: 'Piso de cocina', description: 'Cambio de baldosas sueltas y nivelación.' },
      { title: 'Muro divisorio', description: 'Muro en drywall para crear un estudio.' },
      { title: 'Arreglo de tejado', description: 'Cambio de tejas y sellado de canales.' },
    ],
    reviews: [
      'El baño quedó muy bonito y terminó antes de lo esperado.',
      'Por fin se acabaron las goteras. Gracias.',
      'Muy organizado, recogía todo cada día.',
      'Hizo varios arreglos en una sola visita a buen precio.',
      'Excelente maestro, muy responsable.',
    ],
  },
  instalaciones: {
    headlines: ['Instalador de aires acondicionados y equipos', 'Instalaciones para el hogar', 'Montaje de televisores, cortinas y accesorios', 'Técnico instalador certificado en alturas'],
    specialties: [
      'Instalo aires acondicionados tipo minisplit con vacío, prueba de fugas y soporte a la medida.',
      'Monto televisores en pared, repisas, cortinas, persianas y accesorios de baño.',
      'Instalo duchas eléctricas, calentadores solares y extractores de olores.',
      'Armo e instalo muebles de caja y gabinetes de cocina.',
    ],
    process: [
      'Reviso el tipo de pared antes de perforar para usar el anclaje correcto.',
      'Tengo curso de trabajo en alturas para instalaciones en fachadas.',
      'Dejo el equipo funcionando y le explico al cliente el mantenimiento básico.',
    ],
    services: [
      { title: 'Instalación de aire minisplit', description: 'Instalación de aire acondicionado minisplit con soporte, tubería de cobre hasta 3 metros, vacío y prueba de funcionamiento.', conditions: 'Equipos de hasta 12.000 BTU. El punto eléctrico se cotiza si no existe.', price: 250_000, unit: 'FIXED' },
      { title: 'Montaje de televisor en pared', description: 'Instalación de soporte fijo o articulado y montaje del televisor, con cables ocultos en canaleta.', conditions: 'Televisores de hasta 75 pulgadas. El cliente compra el soporte.', price: 60_000, unit: 'FIXED' },
      { title: 'Instalación de cortinas y persianas', description: 'Instalación de cortineros, rieles, persianas enrollables y blackout.', conditions: 'Precio por ventana.', price: 35_000, unit: 'FIXED' },
      { title: 'Instalación de ducha eléctrica', description: 'Instalación de ducha eléctrica con breaker independiente y cable del calibre correcto.', conditions: 'Hasta 8 metros desde el tablero.', price: 110_000, unit: 'FIXED' },
      { title: 'Armado de muebles', description: 'Armado e instalación de muebles de caja, escritorios, camas y closets prefabricados.', conditions: 'Precio por hora.', price: 30_000, unit: 'HOUR' },
    ],
    works: [
      { title: 'Minisplit en habitación', description: 'Aire de 12.000 BTU con tubería oculta.' },
      { title: 'Televisor en pared', description: 'Soporte articulado y cables ocultos.' },
      { title: 'Persianas en apartamento', description: 'Instalación de seis persianas enrollables.' },
      { title: 'Ducha eléctrica', description: 'Ducha con circuito independiente.' },
      { title: 'Calentador solar', description: 'Instalación en terraza con soporte metálico.' },
      { title: 'Armado de closet', description: 'Closet prefabricado armado y anclado a la pared.' },
    ],
    reviews: [
      'El aire quedó perfecto y sin ruidos.',
      'Montó el televisor en media hora y escondió los cables.',
      'Muy cuidadoso al perforar, no dañó nada.',
      'Me explicó cómo hacerle mantenimiento al aire.',
      'Puntual y amable. Lo recomiendo.',
    ],
  },
  'servicios-tecnicos': {
    headlines: ['Técnico en electrodomésticos', 'Reparación de neveras y lavadoras', 'Refrigeración y aires acondicionados', 'Servicio técnico a domicilio'],
    specialties: [
      'Reparo neveras que no enfrían, lavadoras que no centrifugan, estufas y hornos.',
      'Hago mantenimiento preventivo a aires acondicionados: limpieza de serpentines, filtros y carga de gas.',
      'Diagnostico tarjetas electrónicas de lavadoras y neveras inverter.',
      'Reviso computadores y televisores: limpieza, cambio de piezas y configuración.',
    ],
    process: [
      'Doy el diagnóstico en la visita y solo cambio repuestos originales o de buena calidad, con garantía.',
      'Si el arreglo cuesta más que comprar un equipo nuevo, se lo digo al cliente con honestidad.',
      'Entrego las piezas cambiadas para que el cliente vea qué se dañó.',
    ],
    services: [
      { title: 'Reparación de neveras', description: 'Diagnóstico y reparación de neveras que no enfrían, hacen ruido o botan agua. Cambio de termostatos, ventiladores y carga de gas.', conditions: 'Repuestos aparte. Garantía de 3 meses en la reparación.', price: 80_000, unit: 'VISIT' },
      { title: 'Reparación de lavadoras', description: 'Reparación de lavadoras que no centrifugan, no desaguan o no encienden. Cambio de bombas, correas, tarjetas y sensores.', conditions: 'Repuestos aparte. Garantía de 3 meses.', price: 75_000, unit: 'VISIT' },
      { title: 'Mantenimiento de aire acondicionado', description: 'Limpieza profunda de unidad interior y exterior, filtros, serpentines y desagüe, con revisión de presión del gas.', conditions: 'Equipos de hasta 24.000 BTU. La recarga de gas se cobra aparte si se necesita.', price: 110_000, unit: 'FIXED' },
      { title: 'Revisión de estufas y hornos', description: 'Reparación de quemadores, encendido eléctrico, termostato y empaques de horno.', conditions: 'Repuestos aparte.', price: 65_000, unit: 'VISIT' },
      { title: 'Soporte de computadores', description: 'Limpieza interna, cambio de disco a estado sólido, formateo e instalación de programas.', conditions: 'Precio de mano de obra; el disco se cotiza.', price: 70_000, unit: 'FIXED' },
    ],
    works: [
      { title: 'Nevera no frost', description: 'Cambio de ventilador del evaporador; volvió a enfriar parejo.' },
      { title: 'Lavadora que no centrifugaba', description: 'Cambio de correa y amortiguadores.' },
      { title: 'Mantenimiento de aires', description: 'Limpieza de cuatro equipos en una oficina.' },
      { title: 'Horno a gas', description: 'Cambio de termostato y empaque de la puerta.' },
      { title: 'Portátil más rápido', description: 'Cambio a disco de estado sólido y limpieza.' },
      { title: 'Tarjeta de lavadora', description: 'Reparación de tarjeta electrónica sin cambiarla completa.' },
    ],
    reviews: [
      'La nevera quedó funcionando el mismo día.',
      'Me mostró la pieza dañada y cobró lo justo.',
      'El aire quedó enfriando como nuevo después del mantenimiento.',
      'Muy honesto, me dijo que no valía la pena cambiar la tarjeta y tenía razón.',
      'Excelente técnico, sabe mucho.',
    ],
  },
  otros: {
    headlines: ['Jardinería y mantenimiento de zonas verdes', 'Limpieza profunda de hogares', 'Jardinero y paisajista', 'Aseo y desinfección de espacios'],
    specialties: [
      'Corto césped, podo setos y árboles pequeños, y hago control de plagas en jardines.',
      'Hago limpieza profunda de casas y apartamentos: cocinas, baños, vidrios y pisos.',
      'Diseño y siembro jardines pequeños con plantas que se adaptan al clima de la ciudad.',
      'Lavo muebles, colchones y tapetes con máquina de inyección y extracción.',
    ],
    process: [
      'Llevo mis herramientas y productos; uso productos biodegradables cuando el cliente lo prefiere.',
      'Acordamos con el cliente qué espacios atender primero y en cuánto tiempo.',
      'Recojo y saco los residuos al terminar.',
    ],
    services: [
      { title: 'Corte de césped y poda', description: 'Corte de césped, bordeado, poda de setos y recolección de residuos.', conditions: 'Jardines de hasta 100 m².', price: 70_000, unit: 'FIXED' },
      { title: 'Limpieza profunda de hogar', description: 'Limpieza a fondo de cocina, baños, vidrios, pisos y polvo en toda la vivienda.', conditions: 'Apartamentos de hasta 80 m². Productos incluidos.', price: 150_000, unit: 'FIXED' },
      { title: 'Lavado de muebles y colchones', description: 'Lavado con máquina de inyección y extracción para muebles, colchones y tapetes.', conditions: 'Precio por puesto o por colchón sencillo.', price: 40_000, unit: 'FIXED' },
      { title: 'Diseño y siembra de jardín', description: 'Diseño sencillo, preparación de tierra, siembra y sistema de riego básico.', conditions: 'Plantas aparte.', price: 200_000, unit: 'FIXED' },
    ],
    works: [
      { title: 'Jardín frontal', description: 'Siembra de plantas ornamentales y piedra decorativa.' },
      { title: 'Limpieza post obra', description: 'Limpieza completa después de una remodelación.' },
      { title: 'Poda de setos', description: 'Poda y mantenimiento mensual.' },
      { title: 'Sala lavada', description: 'Lavado de sala de cinco puestos.' },
      { title: 'Césped recuperado', description: 'Resiembra y abono de zona verde.' },
    ],
    reviews: [
      'Dejó el jardín precioso.',
      'La casa quedó impecable, muy recomendada.',
      'Puntual y muy dedicada en su trabajo.',
      'Los muebles quedaron como nuevos.',
    ],
  },
};

// ---------------------------------------------------------------- Personas

type P = { name: string; g: 'm' | 'f'; city: keyof typeof CITIES; trades: string[]; years: number; plan: 'BASIC' | 'INTERMEDIATE' | 'PREMIUM' };
const PEOPLE: P[] = [
  // Cartagena (12)
  { name: 'José Luis Pérez Marrugo', g: 'm', city: 'ctg', trades: ['plomeria', 'instalaciones'], years: 15, plan: 'PREMIUM' },
  { name: 'Yesenia Arrieta Ortiz', g: 'f', city: 'ctg', trades: ['electricidad'], years: 9, plan: 'INTERMEDIATE' },
  { name: 'Rafael Contreras Julio', g: 'm', city: 'ctg', trades: ['carpinteria'], years: 20, plan: 'BASIC' },
  { name: 'Luis Fernando Bustillo', g: 'm', city: 'ctg', trades: ['pintura', 'reparaciones'], years: 7, plan: 'INTERMEDIATE' },
  { name: 'Kelly Johana Mercado', g: 'f', city: 'ctg', trades: ['cerrajeria'], years: 5, plan: 'BASIC' },
  { name: 'Álvaro Cassiani Torres', g: 'm', city: 'ctg', trades: ['servicios-tecnicos'], years: 11, plan: 'PREMIUM' },
  { name: 'Dayana Puello Herrera', g: 'f', city: 'ctg', trades: ['otros'], years: 6, plan: 'BASIC' },
  { name: 'Ever Barrios Cabarcas', g: 'm', city: 'ctg', trades: ['reparaciones'], years: 18, plan: 'INTERMEDIATE' },
  { name: 'Wilmer Zúñiga Padilla', g: 'm', city: 'ctg', trades: ['instalaciones', 'electricidad'], years: 8, plan: 'INTERMEDIATE' },
  { name: 'Mónica Castro Villalba', g: 'f', city: 'ctg', trades: ['pintura'], years: 4, plan: 'BASIC' },
  { name: 'Hernando Batista Gómez', g: 'm', city: 'ctg', trades: ['plomeria'], years: 22, plan: 'BASIC' },
  { name: 'Andrea Salas Pacheco', g: 'f', city: 'ctg', trades: ['servicios-tecnicos'], years: 7, plan: 'INTERMEDIATE' },
  // El Carmen de Bolívar (8)
  { name: 'Orlando Tovar Rojas', g: 'm', city: 'carmen', trades: ['plomeria', 'reparaciones'], years: 14, plan: 'INTERMEDIATE' },
  { name: 'Ledys Martínez Ariza', g: 'f', city: 'carmen', trades: ['otros'], years: 8, plan: 'BASIC' },
  { name: 'Robinson Mendoza Ochoa', g: 'm', city: 'carmen', trades: ['electricidad'], years: 12, plan: 'PREMIUM' },
  { name: 'Nelson Rivera Díaz', g: 'm', city: 'carmen', trades: ['carpinteria'], years: 25, plan: 'INTERMEDIATE' },
  { name: 'Yuranis Ospino Fuentes', g: 'f', city: 'carmen', trades: ['pintura'], years: 3, plan: 'BASIC' },
  { name: 'Edwin Romero Chamorro', g: 'm', city: 'carmen', trades: ['servicios-tecnicos', 'instalaciones'], years: 10, plan: 'INTERMEDIATE' },
  { name: 'Iván Narváez Pérez', g: 'm', city: 'carmen', trades: ['cerrajeria'], years: 9, plan: 'BASIC' },
  { name: 'Carmen Elena Viloria', g: 'f', city: 'carmen', trades: ['reparaciones'], years: 6, plan: 'BASIC' },
  // Barranquilla (8)
  { name: 'Jesús David Charris', g: 'm', city: 'baq', trades: ['electricidad', 'instalaciones'], years: 13, plan: 'PREMIUM' },
  { name: 'Katherine Fontalvo De la Hoz', g: 'f', city: 'baq', trades: ['otros'], years: 5, plan: 'INTERMEDIATE' },
  { name: 'Alfonso Polo Ahumada', g: 'm', city: 'baq', trades: ['plomeria'], years: 17, plan: 'INTERMEDIATE' },
  { name: 'Brayan Escorcia Molina', g: 'm', city: 'baq', trades: ['servicios-tecnicos'], years: 6, plan: 'BASIC' },
  { name: 'Liliana Barraza Orozco', g: 'f', city: 'baq', trades: ['pintura', 'reparaciones'], years: 10, plan: 'INTERMEDIATE' },
  { name: 'Jairo Coll Mendoza', g: 'm', city: 'baq', trades: ['carpinteria'], years: 19, plan: 'PREMIUM' },
  { name: 'Fabián Rodelo Silva', g: 'm', city: 'baq', trades: ['cerrajeria'], years: 12, plan: 'BASIC' },
  { name: 'Sandra Milena Pertuz', g: 'f', city: 'baq', trades: ['instalaciones'], years: 4, plan: 'BASIC' },
  // Bogotá (8)
  { name: 'Diego Alejandro Rincón', g: 'm', city: 'bog', trades: ['plomeria', 'instalaciones'], years: 10, plan: 'INTERMEDIATE' },
  { name: 'Natalia Bermúdez Cano', g: 'f', city: 'bog', trades: ['electricidad'], years: 8, plan: 'PREMIUM' },
  { name: 'Germán Pinzón Rubio', g: 'm', city: 'bog', trades: ['carpinteria'], years: 21, plan: 'INTERMEDIATE' },
  { name: 'Óscar Iván Moreno', g: 'm', city: 'bog', trades: ['pintura'], years: 12, plan: 'BASIC' },
  { name: 'Paula Andrea Suárez', g: 'f', city: 'bog', trades: ['servicios-tecnicos'], years: 9, plan: 'INTERMEDIATE' },
  { name: 'Mauricio Lozano Pardo', g: 'm', city: 'bog', trades: ['reparaciones'], years: 16, plan: 'PREMIUM' },
  { name: 'Ricardo Ávila Forero', g: 'm', city: 'bog', trades: ['cerrajeria'], years: 14, plan: 'BASIC' },
  { name: 'Viviana Rojas Téllez', g: 'f', city: 'bog', trades: ['otros'], years: 7, plan: 'BASIC' },
  // Medellín (7)
  { name: 'Juan Camilo Restrepo', g: 'm', city: 'med', trades: ['electricidad', 'servicios-tecnicos'], years: 11, plan: 'PREMIUM' },
  { name: 'Luisa Fernanda Zapata', g: 'f', city: 'med', trades: ['pintura'], years: 6, plan: 'INTERMEDIATE' },
  { name: 'Héctor Arango Vélez', g: 'm', city: 'med', trades: ['carpinteria'], years: 24, plan: 'INTERMEDIATE' },
  { name: 'Sebastián Gómez Ochoa', g: 'm', city: 'med', trades: ['plomeria'], years: 8, plan: 'BASIC' },
  { name: 'Claudia Patricia Henao', g: 'f', city: 'med', trades: ['otros'], years: 12, plan: 'BASIC' },
  { name: 'Wilson Cardona Ríos', g: 'm', city: 'med', trades: ['reparaciones', 'instalaciones'], years: 15, plan: 'INTERMEDIATE' },
  { name: 'Andrés Felipe Montoya', g: 'm', city: 'med', trades: ['cerrajeria'], years: 7, plan: 'BASIC' },
  // Sincelejo (7)
  { name: 'Eliécer Ruiz Montes', g: 'm', city: 'sinc', trades: ['plomeria', 'reparaciones'], years: 13, plan: 'INTERMEDIATE' },
  { name: 'Marelvis Paternina Salgado', g: 'f', city: 'sinc', trades: ['otros'], years: 9, plan: 'BASIC' },
  { name: 'Jhon Jairo Vergara', g: 'm', city: 'sinc', trades: ['electricidad'], years: 10, plan: 'PREMIUM' },
  { name: 'Adolfo Medrano Benítez', g: 'm', city: 'sinc', trades: ['carpinteria'], years: 18, plan: 'BASIC' },
  { name: 'Rosa Angélica Pérez', g: 'f', city: 'sinc', trades: ['pintura'], years: 5, plan: 'BASIC' },
  { name: 'Yeison Atencia Lora', g: 'm', city: 'sinc', trades: ['servicios-tecnicos', 'instalaciones'], years: 8, plan: 'INTERMEDIATE' },
  { name: 'Duvan Mercado Sierra', g: 'm', city: 'sinc', trades: ['cerrajeria'], years: 6, plan: 'BASIC' },
];

// El Carmen de Bolívar (npm run demo:pros -- carmen): 30 profesionales más
type PC = Omit<P, 'city'>;
const PEOPLE_CARMEN: PC[] = [
  { name: 'Álvaro José Pérez Tovar', g: 'm', trades: ['plomeria'], years: 16, plan: 'PREMIUM' },
  { name: 'Diana Marcela Rojas', g: 'f', trades: ['otros'], years: 7, plan: 'BASIC' },
  { name: 'Luis Eduardo Arrieta', g: 'm', trades: ['electricidad', 'instalaciones'], years: 12, plan: 'INTERMEDIATE' },
  { name: 'Yair Antonio Meza', g: 'm', trades: ['carpinteria'], years: 21, plan: 'INTERMEDIATE' },
  { name: 'Roxana Isabel Díaz', g: 'f', trades: ['pintura'], years: 6, plan: 'BASIC' },
  { name: 'Wilfrido Herrera Caro', g: 'm', trades: ['reparaciones', 'plomeria'], years: 19, plan: 'PREMIUM' },
  { name: 'Jhonatan Vides Salas', g: 'm', trades: ['servicios-tecnicos'], years: 8, plan: 'INTERMEDIATE' },
  { name: 'Ana Milena Ochoa', g: 'f', trades: ['otros'], years: 10, plan: 'BASIC' },
  { name: 'Ramiro Fuentes Ballestas', g: 'm', trades: ['cerrajeria'], years: 14, plan: 'BASIC' },
  { name: 'Erick David Romero', g: 'm', trades: ['instalaciones'], years: 5, plan: 'BASIC' },
  { name: 'Leidy Johana Torres', g: 'f', trades: ['servicios-tecnicos'], years: 9, plan: 'INTERMEDIATE' },
  { name: 'Ismael Paternina Ruiz', g: 'm', trades: ['electricidad'], years: 23, plan: 'PREMIUM' },
  { name: 'Darwin Chamorro Mejía', g: 'm', trades: ['reparaciones'], years: 11, plan: 'INTERMEDIATE' },
  { name: 'Keila Mercado Castro', g: 'f', trades: ['pintura', 'reparaciones'], years: 8, plan: 'INTERMEDIATE' },
  { name: 'Hernán Viloria Gómez', g: 'm', trades: ['carpinteria'], years: 30, plan: 'BASIC' },
  { name: 'Osvaldo Narváez Lora', g: 'm', trades: ['plomeria', 'instalaciones'], years: 9, plan: 'INTERMEDIATE' },
  { name: 'Yesica Paola Ariza', g: 'f', trades: ['otros'], years: 4, plan: 'BASIC' },
  { name: 'Edgardo Benítez Sierra', g: 'm', trades: ['servicios-tecnicos', 'electricidad'], years: 15, plan: 'PREMIUM' },
  { name: 'Carlos Mario Ospino', g: 'm', trades: ['cerrajeria'], years: 7, plan: 'BASIC' },
  { name: 'Marta Lucía Pérez', g: 'f', trades: ['reparaciones'], years: 12, plan: 'BASIC' },
  { name: 'Jorge Iván Tovar', g: 'm', trades: ['electricidad'], years: 6, plan: 'BASIC' },
  { name: 'Nelly Contreras Julio', g: 'f', trades: ['pintura'], years: 11, plan: 'INTERMEDIATE' },
  { name: 'Robert Acuña Montes', g: 'm', trades: ['instalaciones', 'servicios-tecnicos'], years: 10, plan: 'INTERMEDIATE' },
  { name: 'Fabio Salgado Villa', g: 'm', trades: ['carpinteria', 'reparaciones'], years: 17, plan: 'PREMIUM' },
  { name: 'Liliana Mendoza Arrieta', g: 'f', trades: ['otros'], years: 6, plan: 'INTERMEDIATE' },
  { name: 'Manuel Ricardo Díaz', g: 'm', trades: ['plomeria'], years: 13, plan: 'BASIC' },
  { name: 'Wendy Patricia Rivera', g: 'f', trades: ['servicios-tecnicos'], years: 5, plan: 'BASIC' },
  { name: 'Ángel Custodio Barrios', g: 'm', trades: ['cerrajeria', 'instalaciones'], years: 20, plan: 'INTERMEDIATE' },
  { name: 'Tomás Elías Martínez', g: 'm', trades: ['pintura'], years: 9, plan: 'BASIC' },
  { name: 'Sindy Lorena Puello', g: 'f', trades: ['electricidad'], years: 7, plan: 'INTERMEDIATE' },
];

const IN_CARMEN = process.argv.includes('carmen');
const TOWN = IN_CARMEN ? { ...CARMEN, areas: CARMEN_BARRIOS.map((b) => b[0]) } : { ...CARTAGENA, areas: BARRIOS.map((b) => b[0]) };
const townPlace = IN_CARMEN ? carmenPlaceFor : placeFor;
const LIST: PC[] = IN_CARMEN ? PEOPLE_CARMEN : PEOPLE;
const PREFIX = IN_CARMEN ? 'demo-carmen-pro' : 'demo-pro';
/** Desplaza las combinaciones de textos y fotos para que no se repitan con las de Cartagena. */
const OFFSET = IN_CARMEN ? 23 : 0;

const FEES = [0, 10_000, 15_000, 20_000, 25_000, 30_000, 35_000, 12_000, 18_000, 8_000];
const RATINGS = [4.9, 4.7, 4.8, 4.5, 4.6, 5.0, 4.4, 4.8, 4.3, 4.9, 4.6, 4.7];
const SCHEDULES: [number[], string, string, string?][] = [
  [[1, 2, 3, 4, 5, 6], '07:00', '18:00', '13:00'],
  [[1, 2, 3, 4, 5], '08:00', '17:00'],
  [[1, 2, 3, 4, 5, 6, 0], '06:00', '20:00', '14:00'],
  [[2, 3, 4, 5, 6], '09:00', '19:00', '15:00'],
  [[1, 3, 5, 6], '07:30', '16:30', '12:00'],
];

const CLIENTS = [
  'Daniela Herrera', 'Andrés Castillo', 'Paola Vergara', 'Julián Ortega', 'Marcela Ríos', 'Camilo Salgado',
  'Tatiana Blanco', 'Fredy Caraballo', 'Mariana Acosta', 'Esteban Navarro', 'Luz Dary Peña', 'Hugo Ballesteros',
];
const SHORT_REVIEWS: Record<number, string[]> = {
  4: ['Buen trabajo, solo se demoró un poco en llegar.', 'Cumplió con lo cotizado. Recomendado.', 'Resolvió el problema, aunque tuvo que volver por un material.'],
  3: ['El trabajo quedó bien pero la comunicación pudo ser mejor.'],
};

// ---------------------------------------------------------------- Utilidades

const pick = <X>(arr: X[], i: number) => arr[((i % arr.length) + arr.length) % arr.length];
const slugify = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

function photosOf(trade: string) {
  const dir = path.join(PHOTOS, trade);
  return fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith('.jpg')).sort().map((f) => `${trade}/${f}`) : [];
}

const uploaded = new Map<string, string>();
async function upload(rel: string, name: string) {
  const cached = uploaded.get(rel);
  if (cached) return cached;
  const url = await storeBuffer(fs.readFileSync(path.join(PHOTOS, rel)), 'image/jpeg', name);
  uploaded.set(rel, url);
  return url;
}

function credit(rel: string) {
  const c = credits[rel];
  if (!c) return '';
  return ` Foto de referencia: ${c.creator ? `${c.creator}, ` : ''}${c.license} (Flickr).`;
}

function ratingsFor(avg: number, n: number): number[] {
  const out: number[] = [];
  let sum = 0;
  for (let i = 0; i < n; i++) {
    const r = Math.min(5, Math.max(3, Math.round(avg * (i + 1) - sum)));
    out.push(r);
    sum += r;
  }
  return out;
}

// ---------------------------------------------------------------- Siembra

const passwordHash = await bcrypt.hash('NetJob2026!', 10);
const cat = Object.fromEntries((await prisma.category.findMany()).map((c) => [c.slug, c.id]));
const plan = Object.fromEntries((await prisma.subscriptionPlan.findMany()).map((p) => [p.code, p]));
if (!cat.plomeria || !plan.BASIC) {
  console.error('Faltan categorías o planes. Ejecuta primero: npm run db:seed');
  process.exit(1);
}
await ensureBuckets();
console.log(`Imágenes en: ${cloudStorage() ? 'Supabase Storage' : 'uploads/ (disco local)'}`);

const clientUsers = [];
for (const [i, name] of CLIENTS.entries()) {
  const email = `demo-cliente-${i + 1}@netjob.co`;
  clientUsers.push(
    await prisma.user.upsert({ where: { email }, update: {}, create: { email, name, role: 'CLIENT', passwordHash, phone: `30${String(10000000 + i * 7919).slice(0, 8)}` } }),
  );
}

// Retratos: los de Cartagena usan los primeros; los de El Carmen, del 41 en adelante
const usedAvatars = IN_CARMEN ? { m: 40, f: 40 } : { m: 0, f: 0 };
const now = new Date();
let created = 0;

for (const [idx, p] of LIST.entries()) {
  const i = idx + OFFSET;
  const n = String(idx + 1).padStart(2, '0');
  const email = `${PREFIX}-${n}@netjob.co`;
  const avatarIdx = ++usedAvatars[p.g];
  if (await prisma.user.findUnique({ where: { email } })) {
    console.log(`Ya existe ${email}`);
    continue;
  }
  // Repartidos por los barrios del municipio elegido
  const place = townPlace(idx);
  const city = TOWN;
  const main = T[p.trades[0]];
  const second = p.trades[1] ? T[p.trades[1]] : null;
  const first = p.name.split(' ')[0];
  const areas = place.areas;

  // Perfil detallado: presentación, especialidades, forma de trabajo y cierre
  const bio = [
    `Soy ${first}, ${p.g === 'f' ? 'técnica' : 'técnico'} con ${p.years} años de experiencia en ${city.name}.`,
    pick(main.specialties, i),
    pick(main.specialties, i + 1),
    second ? pick(second.specialties, i) : null,
    pick(main.process, i),
    pick(main.process, i + 1),
    `Atiendo en ${areas.join(', ')} y barrios cercanos. Escríbeme por el chat de NetJob y coordinamos la visita.`,
  ]
    .filter(Boolean)
    .join(' ');

  // Ubicación: entre 0,8 y 7 km del centro de la ciudad, en distintas direcciones
  const { lat, lng } = place;

  const pl = plan[p.plan];
  const maxServices = pl.maxServices ?? 5;
  const maxPortfolio = Math.min(pl.maxPortfolio ?? 6, 6);
  const [days, from, to, sat] = pick(SCHEDULES, i);
  const fee = pick(FEES, i);

  const avatarFile = `avatars/${p.g === 'm' ? 'men' : 'women'}-${avatarIdx}.jpg`;
  const avatarUrl = fs.existsSync(path.join(PHOTOS, avatarFile)) ? await upload(avatarFile, `${IN_CARMEN ? 'demo-carmen-avatar' : 'demo-avatar'}-${n}.jpg`) : null;

  // Portafolio: fotos del oficio principal (y una del segundo si lo hay), sin repetir entre vecinos
  const mainPhotos = photosOf(p.trades[0]);
  const secondPhotos = p.trades[1] ? photosOf(p.trades[1]) : [];
  const count = Math.min(maxPortfolio, 3 + (i % 3));
  const portfolio: { title: string; description: string; imageUrl: string }[] = [];
  for (let k = 0; k < count; k++) {
    const useSecond = second && k === count - 1 && secondPhotos.length;
    const pool = useSecond ? secondPhotos : mainPhotos;
    if (!pool.length) continue;
    const rel = pick(pool, i * 3 + k);
    const work = useSecond ? pick(second!.works, i + k) : pick(main.works, i + k);
    portfolio.push({
      title: `${work.title} · ${pick(areas, k)}`,
      description: `${work.description}${credit(rel)}`,
      imageUrl: await upload(rel, `demo-${rel.replace('/', '-')}`),
    });
  }

  const services: (Svc & { slug: string })[] = [
    ...main.services.slice(0, Math.min(maxServices, second ? 2 : 3)).map((s, k) => ({ ...pick(main.services, i + k), slug: p.trades[0] })),
    ...(second ? [{ ...pick(second.services, i), slug: p.trades[1] }] : []),
  ].slice(0, maxServices);
  // Precios con pequeñas variaciones entre profesionales (múltiplos de 5.000)
  const vary = (price: number) => (price < 50_000 ? price : Math.round((price * (0.9 + ((i * 7) % 25) / 100)) / 5000) * 5000);

  const user = await prisma.user.create({
    data: {
      email, name: p.name, role: 'PROFESSIONAL', city: city.name, department: city.dept, passwordHash, avatarUrl,
      phone: `31${String(20000000 + i * 104729).slice(0, 8)}`,
      professional: {
        create: {
          headline: `${pick(main.headlines, i)}${second ? ` · ${pick(second.headlines, i + 1).toLowerCase()}` : ''}`.slice(0, 120),
          bio: bio.slice(0, 2000),
          yearsExperience: p.years,
          city: city.name,
          coverageArea: `${areas.join(', ')} y alrededores`,
          lat, lng,
          diagnosticFee: fee,
          verified: true,
          verificationStatus: 'APPROVED',
          verificationSubmittedAt: new Date(now.getTime() - 40 * 864e5),
          verificationReviewedAt: new Date(now.getTime() - 38 * 864e5),
          rulesAcceptedAt: new Date(now.getTime() - 41 * 864e5),
          trainingPassedAt: new Date(now.getTime() - 41 * 864e5),
          trainingScore: 21 + (i % 5),
          trainingAttempts: 1 + (i % 2),
          isAvailable: i % 9 !== 4,
          featuredUntil: p.plan === 'PREMIUM' ? new Date(now.getTime() + 20 * 864e5) : null,
          boostUntil: pick(RATINGS, i) >= 4.8 ? new Date(now.getTime() + 25 * 864e5) : null,
          categories: { connect: p.trades.map((t) => ({ id: cat[t] })) },
          availability: {
            create: days.map((d) => ({ dayOfWeek: d, startTime: from, endTime: d === 6 && sat ? sat : d === 0 ? '12:00' : to })),
          },
          subscriptions: {
            create: { planId: pl.id, status: 'ACTIVE', startsAt: new Date(now.getTime() - 10 * 864e5), endsAt: new Date(now.getTime() + 120 * 864e5) },
          },
          portfolio: { create: portfolio },
        },
      },
    },
    include: { professional: true },
  });
  const proId = user.professional!.id;
  const svcIds: string[] = [];
  for (const s of services) {
    const svc = await prisma.service.create({
      data: {
        professionalId: proId, categoryId: cat[s.slug], title: s.title, description: s.description,
        price: vary(s.price), priceUnit: s.unit, conditions: `${s.conditions} El valor final se confirma después de la visita de diagnóstico.`,
        coverageArea: `${city.name}: ${areas.join(', ')}`,
        photos: portfolio.length ? [portfolio[0].imageUrl] : [],
      },
    });
    svcIds.push(svc.id);
  }

  // Reseñas de servicios finalizados (cada una con su solicitud, como en la app)
  const nReviews = 3 + ((i * 5) % 9);
  const ratings = ratingsFor(pick(RATINGS, i), nReviews);
  for (const [k, rating] of ratings.entries()) {
    const client = pick(clientUsers, i + k * 5);
    const when = new Date(now.getTime() - (k * 11 + 3 + (i % 7)) * 864e5);
    when.setUTCHours(14 + (k % 5), 0, 0, 0);
    const svcIndex = k % services.length;
    const price = vary(services[svcIndex].price);
    const request = await prisma.serviceRequest.create({
      data: {
        clientId: client.id, professionalId: proId, serviceId: svcIds[svcIndex],
        description: `${services[svcIndex].title}: ${pick(T[services[svcIndex].slug].works, k).description}`,
        address: `${pick(city.areas, i + k)}, ${city.name}`,
        lat: lat + ((k % 3) - 1) * 0.01, lng: lng + ((k % 2) - 0.5) * 0.01,
        scheduledAt: when, status: 'COMPLETED', diagnosticFee: fee, agreedPrice: price,
        quoteNote: 'Mano de obra y materiales básicos según lo revisado en la visita.',
        clientConfirmedAt: when, proConfirmedAt: when,
        warrantyUntil: new Date(when.getTime() + 30 * 864e5),
        createdAt: new Date(when.getTime() - 2 * 864e5),
        history: {
          create: [
            { toStatus: 'PENDING', changedById: client.id, createdAt: new Date(when.getTime() - 2 * 864e5), note: 'Solicitud creada' },
            { fromStatus: 'PENDING', toStatus: 'ACCEPTED', changedById: user.id, createdAt: new Date(when.getTime() - 2 * 864e5 + 3600e3) },
            { fromStatus: 'ACCEPTED', toStatus: 'IN_PROGRESS', changedById: user.id, createdAt: when },
            { fromStatus: 'IN_PROGRESS', toStatus: 'COMPLETED', changedById: user.id, createdAt: new Date(when.getTime() + 3 * 3600e3), note: 'Ambas partes confirmaron' },
          ],
        },
      },
    });
    const comment = rating === 5 ? pick(T[services[svcIndex].slug].reviews, i + k) : pick(SHORT_REVIEWS[rating] ?? SHORT_REVIEWS[4], k);
    await prisma.review.create({
      data: { requestId: request.id, authorId: client.id, professionalId: proId, rating, comment, createdAt: new Date(when.getTime() + 5 * 3600e3) },
    });
  }
  const agg = await prisma.review.aggregate({ where: { professionalId: proId, hidden: false }, _avg: { rating: true }, _count: true });
  await prisma.professionalProfile.update({
    where: { id: proId },
    data: { ratingAvg: Math.round((agg._avg.rating ?? 0) * 10) / 10, ratingCount: agg._count },
  });
  created++;
  console.log(`${n}. ${p.name} · ${city.name} · ${p.trades.join(' + ')} · ${p.plan} · visita ${fee ? `$${fee.toLocaleString('es-CO')}` : 'gratis'} · ${portfolio.length} fotos · ${nReviews} reseñas`);
}

console.log(`\n${created} profesionales creados en ${TOWN.name} (correo ${PREFIX}-NN@netjob.co, contraseña NetJob2026!)`);
await prisma.$disconnect();
