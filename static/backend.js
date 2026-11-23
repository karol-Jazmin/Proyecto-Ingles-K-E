/* Conexión del juego y del panel con su "backend". Se elige solo, en este orden:
     1) Nube (Supabase): si static/config.js tiene la dirección y la clave -> TODO se guarda en la base de datos.
     2) Servidor propio (python3 app.py o PythonAnywhere): si responde /api/game.
     3) Modo práctica (solo juego, sin guardar): si no hay nada de lo anterior. */
(() => {
  const cfg = window.EQ_CONFIG || {};
  const CLOUD = !!(cfg.SUPABASE_URL && cfg.SUPABASE_KEY);
  const KEY = 'eq_admin_token';
  const realFetch = window.fetch.bind(window);
  const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
  const store = (v) => { try { v ? localStorage.setItem(KEY, v) : localStorage.removeItem(KEY); } catch (e) {} };
  const stored = () => { try { return localStorage.getItem(KEY); } catch (e) { return null; } };

  /* ---------------- 1) Nube (Supabase) ---------------- */
  const csvCell = (v) => { let t = String(v == null ? '' : v); if (/^[=+\-@]/.test(t)) t = "'" + t; return '"' + t.replace(/"/g, '""') + '"'; };
  async function cloud(method, path, body) {
    const headers = { 'Content-Type': 'application/json', apikey: cfg.SUPABASE_KEY };
    if (/^eyJ/.test(cfg.SUPABASE_KEY)) headers.Authorization = 'Bearer ' + cfg.SUPABASE_KEY;
    let r;
    try {
      r = await realFetch(cfg.SUPABASE_URL.replace(/\/+$/, '') + '/rest/v1/rpc/eq_api', { method: 'POST', headers,
        body: JSON.stringify({ p_method: method, p_path: path, p_body: body || {}, p_token: stored() }) });
    } catch (e) { return json({ error: 'No se pudo conectar con la base de datos. Revisa tu internet.' }, 503); }
    let out = null; try { out = await r.json(); } catch (e) {}
    if (!r.ok || !out || typeof out.status !== 'number') {
      return json({ error: 'No se pudo conectar con la base de datos. Revisa la configuración (config.js) y que ejecutaste setup.sql en Supabase.' }, 503);
    }
    const { status, data } = out;
    if (path === '/api/admin/login' && status === 200) { store(data.token); return json({ ok: true }); }
    if (path === '/api/admin/logout') store(null);
    if (status === 401 && path.startsWith('/api/admin/') && path !== '/api/admin/login') store(null);
    if (path === '/api/admin/export.csv' && status === 200) {
      const head = ['Nombre completo', 'Ciclo', 'Curso', 'Fecha', 'Mundo', 'Nivel', 'Pregunta', 'Respuesta elegida', 'Respuesta correcta', '¿Correcta?', 'N° de intento'];
      const text = '﻿' + [head, ...data.rows].map((row) => row.map(csvCell).join(',')).join('\r\n');
      return new Response(text, { status: 200, headers: { 'Content-Type': 'text/csv; charset=utf-8' } });
    }
    return json(data, status);
  }

  /* ---------------- 3) Modo práctica (sin guardar) ---------------- */
  const SETTINGS = {
  "title": "English Quest: El Desafío del Sílabo",
  "subtitle": "Módulo Formativo N° 2 · Interpretación y Redacción de Textos",
  "instructions": "Recorrerás 4 mundos basados en los indicadores de logro del sílabo.\nCada mundo tiene preguntas de opción múltiple y retos prácticos.\nSi respondes bien, avanzas; si fallas, podrás reintentar.",
  "final_message": "Has recorrido con éxito las 17 sesiones del sílabo de Interpretación y Redacción de Textos para Diseño y Programación Web. ¡Estás preparado(a) para tu evaluación final!"
};
  const WORLDS = [
  {
    "id": 1,
    "position": 0,
    "name": "Pasado y Voz Pasiva",
    "description": "Sesiones 1 a 4",
    "theme": "cielo",
    "medal": "bronce",
    "checkpoint_text": "¡Has superado el Bloque 1! Dominaste el Pasado Simple y la Voz Pasiva (Sesiones 1 a 4).",
    "character": {
      "skin": "#f2c9a0",
      "hair": "#8a4b2d",
      "hairStyle": "bun",
      "outfit": "#a3237c",
      "outfitStyle": "robe",
      "accessory": "none"
    },
    "questions": [
      {
        "id": 1,
        "world_id": 1,
        "label": "Nivel 1 - Reto 1",
        "objective": "Utiliza el Simple Past empleando verbos regulares e irregulares.",
        "prompt": "¿Cuál es la forma correcta en pasado del verbo code y el verbo be (para the server)?",
        "options": [
          "coded / were",
          "code / was",
          "coded / was"
        ],
        "correct": 2
      },
      {
        "id": 2,
        "world_id": 1,
        "label": "Nivel 1 - Reto 2",
        "objective": "Identifica la estructura de la voz pasiva en presente.",
        "prompt": "En tu carrera lees documentación técnica. ¿Cómo se dice \"El código es compilado\"?",
        "options": [
          "The code is compiled",
          "The code compiles",
          "The code was compiled"
        ],
        "correct": 0
      },
      {
        "id": 3,
        "world_id": 1,
        "label": "Nivel 1 - Reto 3",
        "objective": "Analiza un texto en voz pasiva del tiempo pasado.",
        "prompt": "Selecciona la oración redactada correctamente en voz pasiva pasada:",
        "options": [
          "The web pages were designed by the developer.",
          "The web pages was design by the developer.",
          "The web pages are designed yesterday."
        ],
        "correct": 0
      }
    ]
  },
  {
    "id": 2,
    "position": 1,
    "name": "Continuos y Futuros",
    "description": "Sesiones 5 a 7",
    "theme": "ciudad",
    "medal": "plata",
    "checkpoint_text": "¡Excelente trabajo! Ya dominas los tiempos continuos y los planes de desarrollo a futuro (Sesiones 5 a 7).",
    "character": {
      "skin": "#f2c9a0",
      "hair": "#8a4b2d",
      "hairStyle": "bun",
      "outfit": "#a3237c",
      "outfitStyle": "robe",
      "accessory": "none"
    },
    "questions": [
      {
        "id": 4,
        "world_id": 2,
        "label": "Nivel 2 - Reto 1",
        "objective": "Comprende la estructura del presente continuo y reglas de gerundio (-ing).",
        "prompt": "¿Cuál es la forma correcta del verbo debug (depurar código) en gerundio?",
        "options": [
          "debuging",
          "debugging",
          "debuged"
        ],
        "correct": 1
      },
      {
        "id": 5,
        "world_id": 2,
        "label": "Nivel 2 - Reto 2",
        "objective": "Expresa planes futuros con going to en situaciones cotidianas y laborales.",
        "prompt": "Completa la frase: \"We _____ launch the new mobile app next week.\"",
        "options": [
          "is going to",
          "are going to",
          "will going to"
        ],
        "correct": 1
      },
      {
        "id": 6,
        "world_id": 2,
        "label": "Nivel 2 - Reto 3",
        "objective": "Auxiliar Will: promesas, predicciones y decisiones de momento.",
        "prompt": "Si un usuario reporta un error en la web y decides arreglarlo al instante, ¿qué dices?",
        "options": [
          "I will fix that bug right now!",
          "I am going to fix it yesterday.",
          "I fix it last week."
        ],
        "correct": 0
      }
    ]
  },
  {
    "id": 3,
    "position": 2,
    "name": "Modales e Imperativos",
    "description": "Sesiones 8 a 14",
    "theme": "noche",
    "medal": "oro",
    "checkpoint_text": "¡Impresionante avance! Has dominado la redacción de instrucciones de usuario y documentación técnica intermedia (Sesiones 8 a 14).",
    "character": {
      "skin": "#f2c9a0",
      "hair": "#8a4b2d",
      "hairStyle": "bun",
      "outfit": "#a3237c",
      "outfitStyle": "robe",
      "accessory": "none"
    },
    "questions": [
      {
        "id": 7,
        "world_id": 3,
        "label": "Nivel 3 - Reto 1",
        "objective": "Usa verbos modales (can, could, should, must) para expresar habilidades y obligaciones.",
        "prompt": "¿Qué modal indica una prohibición estricta de seguridad informática?",
        "options": [
          "Mustn't",
          "Can",
          "Might"
        ],
        "correct": 0
      },
      {
        "id": 8,
        "world_id": 3,
        "label": "Nivel 3 - Reto 2",
        "objective": "Emplea verbos imperativos elaborando instrucciones y advertencias (Don't + verb).",
        "prompt": "Traduce la advertencia de sistema: \"No borre la base de datos\".",
        "options": [
          "You don't delete the database.",
          "Don't delete the database!",
          "Let's delete the database."
        ],
        "correct": 1
      },
      {
        "id": 9,
        "world_id": 3,
        "label": "Nivel 3 - Reto 3",
        "objective": "Práctica intermedia integrando voz pasiva, will y going to.",
        "prompt": "¿Cuál de los siguientes enunciados redacta correctamente un objetivo de desarrollo web?",
        "options": [
          "\"Next month, I will optimize the website loading speed.\"",
          "\"Next month, I optimizing website speed.\"",
          "\"Next month, website speed was optimize.\""
        ],
        "correct": 0
      }
    ]
  },
  {
    "id": 4,
    "position": 3,
    "name": "Reported Speech y Cierre",
    "description": "Sesiones 15 a 17",
    "theme": "atardecer",
    "medal": "trofeo",
    "checkpoint_text": "¡Completaste el último mundo! Ya sabes reportar lo que dicen los clientes y redactar tu proyecto final.",
    "character": {
      "skin": "#f2c9a0",
      "hair": "#8a4b2d",
      "hairStyle": "bun",
      "outfit": "#a3237c",
      "outfitStyle": "robe",
      "accessory": "none"
    },
    "questions": [
      {
        "id": 10,
        "world_id": 4,
        "label": "Nivel 4 - Reto 1",
        "objective": "Analiza el discurso indirecto (Reported Speech) en tiempos presentes y pasados.",
        "prompt": "Si un cliente dice en presente: \"I need an online store\", ¿cómo cambia el verbo en reported speech (pasado)?",
        "options": [
          "needed (pasa a pasado simple)",
          "needing",
          "Se queda exactamente igual sin cambios."
        ],
        "correct": 0
      },
      {
        "id": 11,
        "world_id": 4,
        "label": "Nivel 4 - Reto Final",
        "objective": "Redacta un texto integrando las diversas estructuras gramaticales referidas a Diseño y Programación Web.",
        "prompt": "Para cerrar con éxito el curso, ¿qué debes demostrar en tu proyecto final?",
        "options": [
          "Solo memorizar etiquetas HTML sin gramática en inglés.",
          "Aplicar de forma coherente tiempos verbales, voz pasiva y redacción técnica vinculada al desarrollo web y móvil.",
          "No entregar nada."
        ],
        "correct": 1
      }
    ]
  }
];
  const tries = {}, solved = new Set(), firstTry = new Set();
  const total = WORLDS.reduce((n, w) => n + w.questions.length, 0);
  const find = (id) => WORLDS.flatMap((w) => w.questions).find((q) => q.id === id);
  async function practice(path, body) {
    await new Promise((r) => setTimeout(r, 120));
    if (path.startsWith('/api/admin/')) return json({ error: 'El panel de la profesora necesita la base de datos conectada (ver config.js).' }, 503);
    if (path === '/api/game') return json({ settings: SETTINGS, worlds: WORLDS.map((w) => ({ ...w, questions: w.questions.map(({ correct, ...q }) => q) })) });
    if (path === '/api/start') {
      if (!body.full_name || body.full_name.trim().length < 3) return json({ error: 'Escribe tu nombre completo.' }, 400);
      if (!body.cycle || !body.cycle.trim()) return json({ error: 'Escribe el ciclo.' }, 400);
      if (!body.course || !body.course.trim()) return json({ error: 'Escribe el curso.' }, 400);
      return json({ ok: true });
    }
    if (path === '/api/check') {
      const q = find(body.question_id); if (!q) return json({ error: 'Pregunta no encontrada.' }, 404);
      const correct = body.choice === q.correct; tries[q.id] = (tries[q.id] || 0) + 1;
      if (correct && !solved.has(q.id)) { solved.add(q.id); if (tries[q.id] === 1) firstTry.add(q.id); }
      return json({ correct, attempt: tries[q.id] });
    }
    if (path === '/api/world_done') {
      const w = WORLDS.find((x) => x.id === body.world_id);
      if (!w || w.questions.some((q) => !solved.has(q.id))) return json({ error: 'Aún faltan preguntas por acertar en este mundo.' }, 400);
      return json({ saved: true, first_try: firstTry.size, total });
    }
    if (path === '/api/finish') return json({ ok: true, first_try: firstTry.size, total });
    return json({ error: 'No disponible.' }, 404);
  }

  /* ---------------- elección automática ---------------- */
  let mode = CLOUD ? 'cloud' : null;
  async function detect() {
    try { const r = await realFetch('/api/game'); const d = await r.json(); mode = r.ok && Array.isArray(d.worlds) ? 'server' : 'practice'; }
    catch (e) { mode = 'practice'; }
    if (mode === 'practice' && document.getElementById('stage')) {
      const note = document.createElement('div'); note.className = 'offline-note';
      note.textContent = 'Modo práctica: tus respuestas no se guardan';
      document.body.append(note);
    }
  }
  window.fetch = async (url, opts = {}) => {
    const path = new URL(String(url), location.href).pathname;
    if (!path.startsWith('/api/')) return realFetch(url, opts);
    if (mode === null) await detect();
    if (mode === 'server') return realFetch(url, opts);
    const method = (opts.method || 'GET').toUpperCase();
    let body = {}; try { body = opts.body ? JSON.parse(opts.body) : {}; } catch (e) {}
    return mode === 'cloud' ? cloud(method, path, body) : practice(path, body);
  };
})();
