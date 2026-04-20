import { Check, Monitor, Smartphone, BookOpen, Sparkles } from "lucide-react"
import { useI18n } from "../lib/i18n"
import SpotlightCard from "./reactbits/SpotlightCard"

const base = import.meta.env.BASE_URL

export default function Pricing() {
  const { t } = useI18n()

  const mioislandFeatures = [
    "pricing.mioisland.f1",
    "pricing.mioisland.f2",
    "pricing.mioisland.f3",
    "pricing.mioisland.f4",
    "pricing.mioisland.f5",
  ] as const

  const codelightFeatures = [
    "pricing.codelight.f1",
    "pricing.codelight.f2",
    "pricing.codelight.f3",
    "pricing.codelight.f4",
    "pricing.codelight.f5",
  ] as const

  return (
    <section id="pricing" className="relative z-20 bg-deep py-20 sm:py-32 px-4 sm:px-6 noise">
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_50%_at_50%_0%,rgba(52,211,153,0.04)_0%,transparent_60%)]" />
      <div className="max-w-5xl mx-auto relative z-10">
        {/* Header */}
        <div style={{ animation: "heroEnter 0.8s ease-out both" }} className="text-center mb-12 sm:mb-20">
          <span className="font-mono text-xs text-green uppercase tracking-[0.3em]">{t("pricing.tag" as any)}</span>
          <h2 className="font-display text-3xl sm:text-4xl sm:text-5xl font-extrabold text-text-primary mt-4">{t("pricing.title" as any)}</h2>
        </div>

        {/* Trial banner — mirrors the pair-setup tutorial's "Free trial auto-starts" message */}
        <div
          style={{ animation: "heroEnter 0.6s ease-out 0.05s both" }}
          className="max-w-3xl mx-auto mb-8 sm:mb-10 flex items-center gap-3 px-5 py-3 rounded-xl bg-green/[0.06] border border-green/20"
        >
          <Sparkles size={16} className="text-green shrink-0" />
          <span className="font-mono text-[10px] sm:text-xs text-green uppercase tracking-[0.2em] shrink-0">
            {t("pricing.trialBanner.label" as any)}
          </span>
          <span className="text-xs sm:text-sm text-text-secondary leading-snug">
            {t("pricing.trialBanner.body" as any)}
          </span>
        </div>

        {/* Cards */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 sm:gap-8">
          {/* MioIsland Card */}
          <SpotlightCard
            className="!rounded-2xl !p-0 !bg-white/[0.02] !border-white/[0.06]"
            spotlightColor="rgba(52, 211, 153, 0.15)"
          >
            <div
              style={{ animation: "heroEnter 0.6s ease-out 0.1s both" }}
              className="p-6 sm:p-8 flex flex-col w-full"
            >
              <div className="flex items-center gap-3 mb-4">
                <div className="w-10 h-10 rounded-xl bg-green/10 border border-green/15 flex items-center justify-center">
                  <Monitor size={20} className="text-green" />
                </div>
                <div>
                  <h3 className="font-display text-xl font-bold text-text-primary">{t("pricing.mioisland.name" as any)}</h3>
                </div>
                <span className="ml-auto font-mono text-xs bg-green/15 text-green border border-green/20 rounded-full px-3 py-1">
                  {t("pricing.mioisland.price" as any)}
                </span>
              </div>
              <p className="text-sm text-text-muted mb-6 leading-relaxed">{t("pricing.mioisland.desc" as any)}</p>
              <ul className="space-y-3 mb-8 flex-1">
                {mioislandFeatures.map((key) => (
                  <li key={key} className="flex items-start gap-3">
                    <Check size={16} className="text-green mt-0.5 shrink-0" />
                    <span className="text-sm text-text-secondary">{t(key as any)}</span>
                  </li>
                ))}
              </ul>
              <a
                href="https://github.com/MioMioOS/MioIsland/releases"
                target="_blank"
                rel="noopener noreferrer"
                className="block w-full text-center font-display font-bold text-sm bg-green text-deep rounded-xl py-3 transition-all duration-300 hover:shadow-[0_0_30px_rgba(52,211,153,0.3)] hover:scale-[1.02]"
              >
                {t("pricing.mioisland.cta" as any)}
              </a>
            </div>
          </SpotlightCard>

          {/* CodeLight Card */}
          <SpotlightCard
            className="!rounded-2xl !p-0 !bg-white/[0.02] !border-white/[0.06]"
            spotlightColor="rgba(52, 211, 153, 0.15)"
          >
            <div
              style={{ animation: "heroEnter 0.6s ease-out 0.2s both" }}
              className="p-6 sm:p-8 flex flex-col w-full"
            >
              <div className="flex items-center gap-3 mb-4">
                <div className="w-10 h-10 rounded-xl bg-green/10 border border-green/15 flex items-center justify-center">
                  <Smartphone size={20} className="text-green" />
                </div>
                <div>
                  <h3 className="font-display text-xl font-bold text-text-primary">{t("pricing.codelight.name" as any)}</h3>
                </div>
                <span className="ml-auto font-mono text-xs bg-green/15 text-green border border-green/20 rounded-full px-3 py-1">
                  {t("pricing.codelight.price" as any)}
                </span>
              </div>
              <p className="text-sm text-text-muted mb-6 leading-relaxed">{t("pricing.codelight.desc" as any)}</p>
              <ul className="space-y-3 mb-8 flex-1">
                {codelightFeatures.map((key) => (
                  <li key={key} className="flex items-start gap-3">
                    <Check size={16} className="text-green mt-0.5 shrink-0" />
                    <span className="text-sm text-text-secondary">{t(key as any)}</span>
                  </li>
                ))}
              </ul>
              <a
                href="https://apps.apple.com/us/app/code-light/id6761744871"
                target="_blank"
                rel="noopener noreferrer"
                className="block w-full text-center font-display font-bold text-sm bg-green text-deep rounded-xl py-3 transition-all duration-300 hover:shadow-[0_0_30px_rgba(52,211,153,0.3)] hover:scale-[1.02]"
              >
                {t("pricing.codelight.cta" as any)}
              </a>
              <a
                href={`${base}pair-setup.html`}
                className="flex items-center justify-center gap-1.5 text-xs text-green/85 hover:text-green mt-3 transition-colors"
              >
                <BookOpen size={12} />
                {t("pricing.codelight.pairTutorial" as any)}
              </a>
              <p className="text-xs text-text-muted mt-3 text-center leading-relaxed">{t("pricing.codelight.future" as any)}</p>
            </div>
          </SpotlightCard>
        </div>

        {/* Feedback CTA */}
        <div style={{ animation: "heroEnter 0.6s ease-out 0.35s both" }} className="mt-12 sm:mt-16 text-center">
          <p className="text-sm sm:text-base text-text-muted max-w-xl mx-auto leading-relaxed">{t("pricing.feedback" as any)}</p>
        </div>
      </div>
    </section>
  )
}
