import { useState } from "react"
import { Plus, Minus } from "lucide-react"
import { AnimatePresence, motion } from "motion/react"
import { useI18n } from "../lib/i18n"

const faqKeys = [1, 2, 3, 4, 5, 6, 7] as const

export default function FAQ() {
  const { t } = useI18n()
  const [openIndex, setOpenIndex] = useState<number | null>(null)

  const toggle = (index: number) => {
    setOpenIndex(openIndex === index ? null : index)
  }

  return (
    <section id="faq" className="relative z-20 bg-deep py-20 sm:py-32 px-4 sm:px-6 noise">
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_50%_at_50%_0%,rgba(124,58,237,0.06)_0%,transparent_60%)]" />
      <div className="max-w-3xl mx-auto relative z-10">
        {/* Header */}
        <div style={{ animation: "heroEnter 0.8s ease-out both" }} className="text-center mb-12 sm:mb-20">
          <span className="font-mono text-xs text-green uppercase tracking-[0.3em]">{t("faq.tag" as any)}</span>
          <h2 className="font-display text-3xl sm:text-4xl sm:text-5xl font-extrabold text-text-primary mt-4">{t("faq.title" as any)}</h2>
        </div>

        {/* Accordion */}
        <div className="space-y-3 sm:space-y-4">
          {faqKeys.map((num, i) => {
            const isOpen = openIndex === num
            return (
              <div
                key={num}
                style={{ animation: `heroEnter 0.6s ease-out ${i * 0.08}s both` }}
                className="glass rounded-2xl transition-all duration-500 hover:shadow-[0_20px_60px_rgba(124,58,237,0.08)]"
              >
                <button
                  onClick={() => toggle(num)}
                  className="w-full flex items-center justify-between gap-4 p-5 sm:p-6 text-left cursor-pointer"
                >
                  <span className="font-display text-sm sm:text-base font-bold text-text-primary">
                    {t(`faq.q${num}` as any)}
                  </span>
                  <span className="shrink-0 w-7 h-7 rounded-lg bg-green/10 border border-green/15 flex items-center justify-center transition-colors duration-300">
                    {isOpen ? (
                      <Minus size={14} className="text-green" />
                    ) : (
                      <Plus size={14} className="text-green" />
                    )}
                  </span>
                </button>
                <AnimatePresence initial={false}>
                  {isOpen && (
                    <motion.div
                      initial={{ height: 0, opacity: 0 }}
                      animate={{ height: "auto", opacity: 1 }}
                      exit={{ height: 0, opacity: 0 }}
                      transition={{ duration: 0.3, ease: "easeInOut" }}
                      className="overflow-hidden"
                    >
                      <div className="px-5 sm:px-6 pb-5 sm:pb-6">
                        <p className="text-sm text-text-muted leading-relaxed">{t(`faq.a${num}` as any)}</p>
                      </div>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            )
          })}
        </div>
      </div>
    </section>
  )
}
