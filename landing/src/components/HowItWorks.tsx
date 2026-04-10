import { useState } from "react"
import { Download, Copy, Check, ExternalLink, Rocket, Zap } from "lucide-react"
import { useI18n } from "../lib/i18n"

const BREW_CMD = "brew install MioMioOS/tap/mioisland"

export default function HowItWorks() {
  const { t } = useI18n()
  const [copied, setCopied] = useState(false)

  const handleCopy = () => {
    navigator.clipboard.writeText(BREW_CMD)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <section id="how-it-works" className="relative z-20 bg-deep py-20 sm:py-32 px-4 sm:px-6 noise">
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_40%_at_50%_100%,rgba(52,211,153,0.04)_0%,transparent_60%)]" />
      <div className="max-w-2xl mx-auto relative z-10">
        <div style={{ animation: 'heroEnter 0.8s ease-out both' }} className="text-center mb-10 sm:mb-14">
          <span className="font-mono text-xs text-green uppercase tracking-[0.3em]">{t("how.tag")}</span>
          <h2 className="font-display text-3xl sm:text-4xl sm:text-5xl font-extrabold text-text-primary mt-4">{t("how.install.title")}</h2>
        </div>

        {/* Main install card */}
        <div style={{ animation: 'heroEnter 0.6s ease-out 0.1s both' }} className="glass rounded-2xl p-6 sm:p-8 border border-green/10">
          {/* Brew terminal */}
          <div className="rounded-xl p-5 mb-4" style={{ background: 'rgba(0,0,0,0.3)' }}>
            <div className="flex items-center gap-1.5 mb-3">
              <div className="w-2.5 h-2.5 rounded-full bg-red-400/60" />
              <div className="w-2.5 h-2.5 rounded-full bg-amber/60" />
              <div className="w-2.5 h-2.5 rounded-full bg-green/60" />
              <span className="flex-1" />
              <button
                onClick={handleCopy}
                className="flex items-center gap-1.5 text-xs text-green/60 hover:text-green transition-colors cursor-pointer px-2 py-1 rounded-md hover:bg-white/[0.04]"
              >
                {copied ? <Check size={12} /> : <Copy size={12} />}
                {copied ? t("how.install.copied") : "Copy"}
              </button>
            </div>
            <code className="font-mono text-sm sm:text-base text-green leading-relaxed block">
              <span className="text-white/20">$</span> {t("how.install.cmd")}
            </code>
          </div>

          {/* DMG alternative */}
          <div className="flex items-center justify-center gap-2.5 mb-6">
            <div className="h-px flex-1 bg-white/[0.06]" />
            <span className="text-xs text-text-muted/40 font-mono">{t("how.install.or")}</span>
            <div className="h-px flex-1 bg-white/[0.06]" />
          </div>

          <a
            href="https://github.com/MioMioOS/MioIsland/releases"
            className="flex items-center justify-center gap-2 w-full py-3 rounded-xl text-sm font-mono text-green/80 hover:text-green transition-all duration-200 hover:bg-green/[0.06] border border-green/10 hover:border-green/20"
          >
            <Download size={14} />
            {t("how.install.dmg")}
            <ExternalLink size={11} className="opacity-50" />
          </a>
        </div>

        {/* What happens next — compact info row */}
        <div style={{ animation: 'heroEnter 0.6s ease-out 0.2s both' }} className="flex flex-col sm:flex-row gap-4 mt-8">
          <div className="flex-1 flex items-start gap-3 px-4 py-3 rounded-xl" style={{ background: 'rgba(52,211,153,0.03)' }}>
            <Rocket size={16} className="text-green/50 mt-0.5 shrink-0" />
            <p className="text-xs text-text-muted leading-relaxed">{t("how.flow.auto")}</p>
          </div>
          <div className="flex-1 flex items-start gap-3 px-4 py-3 rounded-xl" style={{ background: 'rgba(52,211,153,0.03)' }}>
            <Zap size={16} className="text-green/50 mt-0.5 shrink-0" />
            <p className="text-xs text-text-muted leading-relaxed">{t("how.flow.result")}</p>
          </div>
        </div>
      </div>
    </section>
  )
}
