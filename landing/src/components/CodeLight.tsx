import { Smartphone, Star, Download, Zap, ShieldCheck, Terminal, Camera, Link, Lock } from "lucide-react"
import { useI18n } from "../lib/i18n"

const GithubIcon = ({ size = 16 }: { size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor">
    <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
  </svg>
)

const base = import.meta.env.BASE_URL

const featureIcons = [Smartphone, ShieldCheck, Terminal, Zap, Camera, Link, Lock]

export default function CodeLight() {
  const { t } = useI18n()

  const screenshots = [
    { src: `${base}codelight/macs-list.png`, label: t("codelight.macs") },
    { src: `${base}codelight/sessions.png`, label: t("codelight.sessions") },
    { src: `${base}codelight/commands.png`, label: t("codelight.commands") },
    { src: `${base}codelight/chat.png`, label: t("codelight.chat") },
    { src: `${base}codelight/settings.png`, label: t("codelight.settings") },
  ]

  const features = [1, 2, 3, 4, 5, 6, 7].map((i) => ({
    Icon: featureIcons[i - 1],
    title: t(`codelight.f${i}.title` as any),
    desc: t(`codelight.f${i}.desc` as any),
  }))

  return (
    <section className="relative z-20 bg-deep py-20 sm:py-32 px-4 sm:px-6 noise overflow-hidden">
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_70%_50%_at_50%_0%,rgba(52,211,153,0.06)_0%,transparent_60%)]" />

      <div className="max-w-5xl mx-auto relative z-10">
        {/* Header */}
        <div className="text-center mb-12 sm:mb-16" style={{ animation: 'heroEnter 0.8s ease-out both' }}>
          <div className="flex items-center justify-center gap-2 mb-4">
            <Smartphone size={16} className="text-green" />
            <span className="font-mono text-xs text-green uppercase tracking-[0.3em]">{t("codelight.tag")}</span>
          </div>

          <h2 className="font-display text-3xl sm:text-5xl font-extrabold text-text-primary">
            📱 {t("codelight.title")}
          </h2>

          <p className="text-base sm:text-lg text-text-muted mt-4 max-w-lg mx-auto italic">
            "{t("codelight.subtitle")}"
          </p>

          <p className="text-sm text-text-muted mt-4 max-w-xl mx-auto leading-relaxed">
            {t("codelight.desc")}
          </p>
        </div>

        {/* Lock screen hero image */}
        <div className="flex justify-center mb-12" style={{ animation: 'heroEnter 0.8s ease-out 0.1s both' }}>
          <img
            src={`${base}codelight/lockscreen.jpeg`}
            alt="Code Light Lock Screen"
            className="w-full max-w-xl rounded-2xl shadow-[0_20px_80px_rgba(52,211,153,0.15)] border border-white/[0.06]"
          />
        </div>

        {/* Screenshot grid */}
        <div className="grid grid-cols-2 sm:grid-cols-5 gap-3 sm:gap-4 mb-16" style={{ animation: 'heroEnter 0.8s ease-out 0.2s both' }}>
          {screenshots.map((s, i) => (
            <div key={i} className="text-center group">
              <div className="rounded-xl overflow-hidden border border-white/[0.06] shadow-lg transition-transform duration-300 group-hover:scale-[1.03]">
                <img src={s.src} alt={s.label} className="w-full h-auto" />
              </div>
              <p className="text-[10px] sm:text-xs text-text-muted mt-2 font-mono">{s.label}</p>
            </div>
          ))}
        </div>

        {/* Feature cards grid */}
        <div style={{ animation: 'heroEnter 0.8s ease-out 0.3s both' }}>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 sm:gap-4 mb-12">
            {features.map((f, i) => (
              <div
                key={i}
                className="group relative rounded-2xl p-5 transition-all duration-300 hover:scale-[1.02]"
                style={{
                  background: 'rgba(52,211,153,0.04)',
                  border: '1px solid rgba(52,211,153,0.12)',
                }}
              >
                <div className="absolute inset-0 rounded-2xl opacity-0 group-hover:opacity-100 transition-opacity duration-300" style={{ background: 'rgba(52,211,153,0.08)' }} />
                <div className="relative z-10">
                  <div className="w-9 h-9 rounded-xl flex items-center justify-center mb-3" style={{ background: 'rgba(52,211,153,0.15)' }}>
                    <f.Icon size={18} className="text-green" />
                  </div>
                  <h4 className="text-sm font-bold text-text-primary mb-1">{f.title}</h4>
                  <p className="text-xs text-text-muted leading-relaxed">{f.desc}</p>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Status + CTA */}
        <div className="text-center" style={{ animation: 'heroEnter 0.8s ease-out 0.4s both' }}>
          <p className="text-xs text-text-muted mb-5">
            <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-green-400/10 border border-green-400/20 text-green-300">
              <span className="w-1.5 h-1.5 rounded-full bg-green-400 animate-pulse" />
              {t("codelight.status")}
            </span>
          </p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-3">
            <a
              href="https://apps.apple.com/us/app/code-light/id6761744871"
              className="inline-flex items-center gap-2.5 px-8 py-3.5 rounded-xl font-mono text-sm text-deep font-bold bg-green transition-all duration-300 hover:scale-[1.03] hover:shadow-[0_0_30px_rgba(52,211,153,0.3)]"
            >
              <Download size={16} />
              {t("codelight.appstore")}
            </a>

            <a
              href="https://github.com/xmqywx/CodeLight"
              className="inline-flex items-center gap-2.5 glass px-8 py-3.5 rounded-xl font-mono text-sm text-green/80 transition-all duration-300 hover:scale-[1.03] hover:text-text-primary hover:shadow-[0_0_30px_rgba(52,211,153,0.1)]"
            >
              <GithubIcon size={16} />
              <Star size={14} />
              {t("codelight.star")}
            </a>
          </div>

          <p className="text-xs text-text-muted/60 mt-4 max-w-md mx-auto">
            {t("codelight.regionNote")}
          </p>
        </div>
      </div>
    </section>
  )
}
