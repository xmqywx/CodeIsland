import { useState } from "react"
import { Download, Copy, Check, Smartphone, Link2, Rocket } from "lucide-react"
import { useI18n } from "../lib/i18n"

const BREW_CMD = "brew install xmqywx/codeisland/codeisland"

export default function HowItWorks() {
  const { t } = useI18n()
  const [copied, setCopied] = useState(false)

  const handleCopy = () => {
    navigator.clipboard.writeText(BREW_CMD)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  const steps = [
    {
      num: "01",
      Icon: Download,
      titleKey: "how.step1.title",
      descKey: "how.step1.desc",
      color: "#34d399",
    },
    {
      num: "02",
      Icon: Smartphone,
      titleKey: "how.step2.title",
      descKey: "how.step2.desc",
      color: "#34d399",
    },
    {
      num: "03",
      Icon: Link2,
      titleKey: "how.step3.title",
      descKey: "how.step3.desc",
      color: "#34d399",
    },
  ]

  return (
    <section id="how-it-works" className="relative z-20 bg-deep py-20 sm:py-32 px-4 sm:px-6 noise">
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_40%_at_50%_100%,rgba(52,211,153,0.04)_0%,transparent_60%)]" />
      <div className="max-w-4xl mx-auto relative z-10">
        <div style={{ animation: 'heroEnter 0.8s ease-out both' }} className="text-center mb-12 sm:mb-16">
          <span className="font-mono text-xs text-green uppercase tracking-[0.3em]">{t("how.tag")}</span>
          <h2 className="font-display text-3xl sm:text-4xl sm:text-5xl font-extrabold text-text-primary mt-4">{t("how.title")}</h2>
        </div>

        {/* 3-step flow */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-12">
          {steps.map((step, i) => (
            <div
              key={step.num}
              style={{ animation: `heroEnter 0.6s ease-out ${i * 0.12}s both` }}
              className="relative glass rounded-2xl p-6 text-center group hover:translate-y-[-4px] transition-all duration-500"
            >
              {/* Step number */}
              <div
                className="font-mono text-4xl font-bold mb-4 opacity-20 group-hover:opacity-40 transition-opacity"
                style={{ color: step.color }}
              >
                {step.num}
              </div>
              <div
                className="w-12 h-12 rounded-xl flex items-center justify-center mx-auto mb-4"
                style={{ background: `${step.color}15`, border: `1px solid ${step.color}25` }}
              >
                <step.Icon size={22} style={{ color: step.color }} />
              </div>
              <h3 className="font-display text-lg font-bold text-text-primary mb-2">
                {t(step.titleKey as any)}
              </h3>
              <p className="text-sm text-text-muted leading-relaxed">
                {t(step.descKey as any)}
              </p>

              {/* Connector arrow (hidden on mobile, shown between cards on desktop) */}
              {i < 2 && (
                <div className="hidden md:block absolute -right-3 top-1/2 -translate-y-1/2 z-10 text-white/10 text-2xl">
                  →
                </div>
              )}
            </div>
          ))}
        </div>

        {/* Brew install card */}
        <div style={{ animation: 'heroEnter 0.6s ease-out 0.4s both' }} className="glass rounded-2xl p-6 sm:p-8 border border-green/10 max-w-2xl mx-auto">
          <div className="text-center mb-4">
            <span className="font-mono text-xs text-green/60">{t("how.step1.title")}</span>
          </div>

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
              <span className="text-white/20">$</span> {BREW_CMD}
            </code>
          </div>

        </div>

        {/* Result hint */}
        <div style={{ animation: 'heroEnter 0.6s ease-out 0.5s both' }} className="flex items-center justify-center gap-3 mt-8 px-4">
          <Rocket size={16} className="text-green/50 shrink-0" />
          <p className="text-sm text-text-muted text-center">{t("how.result")}</p>
        </div>
      </div>
    </section>
  )
}
