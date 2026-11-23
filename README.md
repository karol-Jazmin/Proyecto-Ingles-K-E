# English Quest

**[▶ Jugar en línea](https://eduarux.github.io/english-quest-v1/)** (para que se guarden las respuestas y funcione el panel, conecta la base de datos: ver abajo).

Juego pixelado con panel de administración y base de datos SQLite. No necesita instalar nada: solo Python 3.8 o superior.

## Cómo ejecutarlo

    python3 app.py

- Juego para estudiantes: http://localhost:8000/
- Panel de la profesora: http://localhost:8000/admin
  - Usuario: `admin`, clave: `admin123` (cámbiala en la pestaña Administradores)

Variables opcionales: `PORT`, `HOST` (usa `0.0.0.0` para abrirlo en la red del aula), `DB_PATH`.
La base de datos `english_quest.db` se crea sola la primera vez, con los 4 mundos del guion.

## Qué puede hacer la administradora
- Resultados: lista de estudiantes (nombre, ciclo, curso), detalle de cada pregunta con cada respuesta e intento, filtros, exportar a CSV.
- Por pregunta: porcentaje de acierto a la primera y promedio de intentos.
- Mundos y preguntas: crear, editar, ordenar y eliminar mundos; cambiar fondo, medalla, mensaje y el personaje guía de cada mundo; editar preguntas y respuestas (2 a 4 opciones).
- Textos: título, subtítulo, instrucciones y mensaje final.
- Administradores: crear otros administradores o profesoras, cambiar claves, eliminar.

## Estudiantes
Al inicio escriben nombre completo, ciclo y curso y crean su personaje. Recorren los mundos y responden (si fallan, reintentan). Al terminar cada mundo sus respuestas se guardan automáticamente en la base de datos, así que la profesora ve el avance aunque no lleguen al final.
Las respuestas correctas nunca se envían al navegador del estudiante: se validan en el servidor.

## Que todo se guarde en GitHub Pages (base de datos en Supabase, gratis)
1. Crea una cuenta en supabase.com y un proyecto nuevo (**New project**). Apunta la contraseña de la base de datos.
2. En el proyecto abre **SQL Editor → New query**, pega todo el contenido de `supabase/setup.sql` y pulsa **Run**. Eso crea las tablas, los 4 mundos y el usuario `admin` (clave inicial `admin123`).
3. Ve a **Project Settings → API** y copia la **Project URL** y la clave **anon public** (o *publishable*).
4. Abre `static/config.js` en GitHub (lápiz ✏️), pega esos dos datos entre las comillas y guarda con **Commit changes**.
5. Espera 1 o 2 minutos y abre la página. Los estudiantes juegan en la dirección normal; la profesora entra con el botón "Iniciar sesión" de la esquina.
6. **Cambia la clave `admin123`** en la pestaña Administradores apenas entres.

Cada respuesta se guarda en la base de datos en el mismo momento. Las respuestas correctas viven solo en la base de datos y nunca llegan al navegador del estudiante.

## Alternativa: servidor propio (PythonAnywhere)
1. Crea una cuenta gratis en pythonanywhere.com (tu dirección será `USUARIO.pythonanywhere.com`).
2. Pestaña **Consoles → Bash**: `git clone https://github.com/Eduarux/english-quest-v1.git`
3. Pestaña **Web → Add a new web app → Manual configuration → Python 3.10**.
4. En **WSGI configuration file** borra todo y pega (cambia `USUARIO`):

        import sys
        path = '/home/USUARIO/english-quest-v1'
        if path not in sys.path:
            sys.path.insert(0, path)
        from eq_wsgi import application

5. Pulsa **Reload**. Cada mes entra a la pestaña Web y pulsa el botón de extender (**Run until ...**) para que no se apague.
