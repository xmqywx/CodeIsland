import { useState } from "react"
import { Download, Rocket, Zap, Copy, Check, ExternalLink } from "lucide-react"
import { useI18n } from "../lib/i18n"

const BREW_CMD = "brew install xmqywx/codeisland/codeisland"

function InstallTerminal() {
  const { t } = useI18n()
  const [copied, setCopied] = useState(false)

  const handleCopy = () => {
    navigator.clipboard.writeText(BREW_CMD)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <div className="glass rounded-xl p-4 mb-3 text-left">
      <div className="flex items-center gap-1.5 mb-2">
        <div className="w-2 h-2 rounded-full bg-red-400/60" />
        <div className="w-2 h-2 rounded-full bg-amber/60" />
        <div className="w-2 h-2 rounded-full bg-green/60" />
        <span className="flex-1" />
        <button
          onClick={handleCopy}
          className="flex items-center gap-1 text-[10px] text-green/60 hover:text-green transition-colors cursor-pointer"
        >
          {copied ? <Check size={10} /> : <Copy size={10} />}
          {copied ? t("how.install.copied") : "Copy"}
        </button>
      </div>
      <code className="font-mono text-xs text-green/80 leading-relaxed block">
        <span className="text-purple-light/40">$</span> {t("how.install.cmd")}
      </code>
    </div>
  )
}

function InstallDmgLink() {
  const { t } = useI18n()
  return (
    <div className="flex items-center justify-center gap-2 mb-5">
      <span className="text-[11px] text-text-muted/50">{t("how.install.or")}</span>
      <a
        href="https://github.com/xmqywx/CodeIsland/releases"
        className="inline-flex items-center gap-1.5 text-[11px] text-green/70 hover:text-green transition-colors"
      >
        <ExternalLink size={10} />
        {t("how.install.dmg")}
      </a>
    </div>
  )
}

export default function HowItWorks() {
  const { t } = useI18n()

  const steps = [
    { Icon: Download, num: "01", cmdKey: "how.install.cmd" as const, titleKey: "how.install.title" as const, descKey: "how.install.desc" as const, isInstall: true },
    { Icon: Rocket, num: "02", cmdKey: "how.launch.cmd" as const, titleKey: "how.launch.title" as const, descKey: "how.launch.desc" as const, isInstall: false },
    { Icon: Zap, num: "03", cmdKey: "how.flow.cmd" as const, titleKey: "how.flow.title" as const, descKey: "how.flow.desc" as const, isInstall: false },
  ]

  return (
    <section id="how-it-works" className="relative z-20 bg-deep py-20 sm:py-32 px-4 sm:px-6 noise">
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_40%_at_50%_100%,rgba(52,211,153,0.04)_0%,transparent_60%)]" />
      <div className="max-w-5xl mx-auto relative z-10">
        <div style={{ animation: 'heroEnter 0.8s ease-out both' }} className="text-center mb-12 sm:mb-20">
          <span className="font-mono text-xs text-green uppercase tracking-[0.3em]">{t("how.tag")}</span>
          <h2 className="font-display text-3xl sm:text-4xl sm:text-5xl font-extrabold text-text-primary mt-4">{t("how.title")}</h2>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 sm:gap-8 relative">
          <div className="hidden md:block absolute top-16 left-[16%] right-[16%] h-px bg-gradient-to-r from-transparent via-purple-accent/20 to-transparent" />
          {steps.map((step, i) => (
            <div key={step.num} style={{ animation: `heroEnter 0.6s ease-out ${i * 0.12}s both` }} className="text-center">
              <div className="relative inline-flex items-center justify-center w-12 h-12 rounded-2xl bg-green/10 border border-green/15 mb-6">
                <step.Icon size={20} className="text-green" />
                <span className="absolute -top-2 -right-2 w-5 h-5 rounded-full bg-deep border border-green/30 flex items-center justify-center font-mono text-[9px] text-green font-bold">{step.num}</span>
              </div>

              {step.isInstall ? (
                <>
                  <InstallTerminal />
                  <InstallDmgLink />
                </>
              ) : (
                <div className="glass rounded-xl p-4 mb-5 text-left">
                  <div className="flex items-center gap-1.5 mb-2">
                    <div className="w-2 h-2 rounded-full bg-red-400/60" />
                    <div className="w-2 h-2 rounded-full bg-amber/60" />
                    <div className="w-2 h-2 rounded-full bg-green/60" />
                  </div>
                  <code className="font-mono text-xs text-green/80 leading-relaxed block">
                    <span className="text-purple-light/40">$</span> {t(step.cmdKey)}
                  </code>
                </div>
              )}

              <h3 className="font-display text-xl font-bold text-text-primary">{t(step.titleKey)}</h3>
              <p className="text-sm text-text-muted mt-2 leading-relaxed">{t(step.descKey)}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
