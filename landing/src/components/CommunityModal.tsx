import { motion, AnimatePresence } from "motion/react"
import { X } from "lucide-react"
import { useEffect } from "react"
import { useI18n } from "../lib/i18n"

interface Props {
  open: boolean
  onClose: () => void
}

export default function CommunityModal({ open, onClose }: Props) {
  const { t } = useI18n()

  // ESC key closes modal
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    document.body.style.overflow = "hidden"
    return () => {
      window.removeEventListener("keydown", onKey)
      document.body.style.overflow = ""
    }
  }, [open, onClose])

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.2 }}
          className="fixed inset-0 z-[100] flex items-center justify-center p-4"
          onClick={onClose}
        >
          {/* Backdrop */}
          <div className="absolute inset-0 bg-black/80 backdrop-blur-md" />

          {/* Modal */}
          <motion.div
            initial={{ opacity: 0, scale: 0.9, y: 20 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.9, y: 20 }}
            transition={{ type: "spring", duration: 0.4, bounce: 0.2 }}
            className="relative max-w-md w-full rounded-3xl overflow-hidden"
            style={{
              background: "rgba(20, 20, 32, 0.95)",
              border: "1px solid rgba(255, 255, 255, 0.08)",
              boxShadow: "0 30px 90px rgba(0, 0, 0, 0.8), 0 0 0 1px rgba(255, 255, 255, 0.04) inset",
            }}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Close button */}
            <button
              onClick={onClose}
              className="absolute top-4 right-4 w-8 h-8 rounded-full flex items-center justify-center text-white/50 hover:text-white hover:bg-white/[0.08] transition-all z-10"
              aria-label={t("community.close")}
            >
              <X size={16} />
            </button>

            {/* Header */}
            <div className="pt-8 pb-4 px-6 text-center">
              <h3 className="font-display text-2xl font-bold text-text-primary">
                {t("community.title")}
              </h3>
              <p className="text-sm text-text-muted mt-2 leading-relaxed">
                {t("community.subtitle")}
              </p>
            </div>

            {/* QR Code */}
            <div className="px-6 pb-6">
              <div className="relative rounded-2xl overflow-hidden bg-white p-3 mx-auto max-w-[280px]">
                <img
                  src={`${import.meta.env.BASE_URL}wechat-qr.jpg`}
                  alt="WeChat Group QR Code"
                  className="w-full h-auto block"
                />
              </div>

              {/* Note */}
              <div className="mt-4 px-2">
                <p className="text-xs text-text-muted text-center leading-relaxed">
                  {t("community.qrNote")}
                </p>
                <p className="text-[10px] text-text-muted/60 text-center leading-relaxed mt-2">
                  {t("community.qrExpiry")}
                </p>
              </div>
            </div>

            {/* Gradient border glow */}
            <div
              className="absolute inset-0 rounded-3xl pointer-events-none"
              style={{
                background: "linear-gradient(135deg, rgba(74,222,128,0.08) 0%, transparent 50%, rgba(124,58,237,0.08) 100%)",
                mixBlendMode: "overlay",
              }}
            />
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
