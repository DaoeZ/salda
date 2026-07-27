<script lang="ts">
  import { BRAND } from '../lib/brand.g';

  /** `g` = invitación a un grupo · `t` = ticket compartido. */
  export let kind: 'g' | 't';
  export let token: string;

  // URL `intent://` de Android: es lo ÚNICO que hace saltar a una app nativa
  // desde un WebView. Los navegadores dentro de WhatsApp o Instagram no
  // resuelven App Links —nunca ceden el enlace al sistema—, así que sin esto
  // el enlace muere aquí por muy verificado que esté el dominio.
  const intentUrl =
    `intent://${location.host}/${kind}/${token}` +
    '#Intent;scheme=https;package=dev.salda.salda_mobile;' +
    `S.browser_fallback_url=${encodeURIComponent(location.href + '?web=1')};end`;

  // `?web=1` corta el bucle: si el fallback nos devuelve aquí, ya no se
  // vuelve a intentar abrir la app.
  const yaIntentado = new URLSearchParams(location.search).has('web');

  if (!yaIntentado) {
    // Reemplaza la entrada del historial para que «atrás» no repita el salto.
    location.replace(intentUrl);
  }

  const titulo =
    kind === 'g' ? 'Te han invitado a un grupo' : 'Te han compartido un gasto';
</script>

<main>
  <p class="marca">{BRAND.appName}</p>
  <h1>{titulo}</h1>
  <p class="cuerpo">
    Ábrelo en la app para {kind === 'g'
      ? 'unirte al grupo'
      : 'ver el gasto y marcar lo tuyo'}.
  </p>

  <a class="boton" href={intentUrl}>Abrir en {BRAND.appName}</a>

  <p class="ayuda">
    ¿No tienes la app? Instálala y vuelve a pulsar el enlace: se abrirá
    directamente aquí.
  </p>

  <details>
    <summary>El enlace no se abre solo</summary>
    <p>
      Algunas apps de mensajería abren los enlaces en su propio navegador y no
      dejan pasar a la aplicación. Toca los tres puntos y elige
      <strong>«Abrir en el navegador»</strong>, o pega este enlace en
      {BRAND.appName} → Unirme con un enlace:
    </p>
    <code>{location.origin}/{kind}/{token}</code>
  </details>
</main>

<style>
  main {
    max-width: 26rem;
    margin: 0 auto;
    padding: 2.5rem 1.25rem;
    text-align: left;
  }
  .marca {
    color: var(--color-primary);
    font-weight: 700;
    letter-spacing: -0.03em;
    margin: 0 0 2rem;
  }
  h1 {
    font-size: 1.6rem;
    line-height: 1.2;
    margin: 0 0 0.5rem;
  }
  .cuerpo {
    color: var(--color-text-secondary);
    margin: 0 0 1.75rem;
  }
  .boton {
    display: block;
    background: var(--color-primary);
    color: var(--color-on-primary);
    text-decoration: none;
    text-align: center;
    padding: 0.9rem 1rem;
    border-radius: var(--radius-button, 10px);
    font-weight: 600;
  }
  .ayuda {
    color: var(--color-text-muted);
    font-size: 0.875rem;
    margin: 1rem 0 2rem;
  }
  details {
    border-top: 1px solid var(--color-border);
    padding-top: 1rem;
    font-size: 0.875rem;
    color: var(--color-text-secondary);
  }
  summary {
    cursor: pointer;
    font-weight: 600;
  }
  code {
    display: block;
    margin-top: 0.5rem;
    padding: 0.6rem;
    background: var(--color-surface-muted);
    border-radius: 8px;
    word-break: break-all;
    font-size: 0.8rem;
  }
</style>
