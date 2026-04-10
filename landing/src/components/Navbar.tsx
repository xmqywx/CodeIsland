import { useState, useEffect } from "react"
import { Download, Globe, Users } from "lucide-react"
import { useI18n } from "../lib/i18n"
import CommunityModal from "./CommunityModal"
import logo from "../lib/logo"

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false)
  const [communityOpen, setCommunityOpen] = useState(false)
  const { lang, setLang, t } = useI18n()

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 40)
    window.addEventListener("scroll", onScroll)
    return () => window.removeEventListener("scroll", onScroll)
  }, [])

  return (
    <>
      <nav
        className={`fixed top-0 left-0 right-0 z-50 transition-all duration-500 ${
          scrolled
            ? "bg-deep/70 backdrop-blur-xl border-b border-white/[0.04]"
            : "bg-transparent"
        }`}
      >
        <div className="max-w-6xl mx-auto px-4 sm:px-6 h-14 sm:h-16 flex items-center justify-between">
          <a href="#" className="flex items-center gap-2 group">
            <img src={logo} alt="CodeIsland" className="w-6 h-6 rounded group-hover:scale-110 transition-transform" />
            <span className="font-mono text-xs sm:text-sm font-bold text-text-primary tracking-[0.15em]">
              CODEISLAND
            </span>
          </a>

          <div className="flex items-center gap-3 sm:gap-6">
            <div className="hidden md:flex items-center gap-6 text-sm text-text-muted">
              {[
                { label: t("nav.demo"), href: "#demo" },
                { label: t("nav.features"), href: "#features" },
                { label: t("nav.howItWorks"), href: "#how-it-works" },
                { label: t("nav.github"), href: "https://github.com/MioMioOS/MioIsland" },
              ].map((item) => (
                <a
                  key={item.label}
                  href={item.href}
                  className="hover:text-text-primary transition-colors relative after:absolute after:bottom-0 after:left-0 after:w-0 after:h-px after:bg-green after:transition-all hover:after:w-full"
                >
                  {item.label}
                </a>
              ))}
            </div>

            {/* Language switcher */}
            <button
              onClick={() => setLang(lang === "zh" ? "en" : "zh")}
              className="flex items-center gap-1 text-xs text-text-muted hover:text-text-primary transition-colors"
            >
              <Globe size={14} />
              <span className="hidden sm:inline">{lang === "zh" ? "EN" : "中文"}</span>
            </button>

            {/* Community button */}
            <button
              onClick={() => setCommunityOpen(true)}
              className="flex items-center gap-1.5 sm:gap-2 text-purple-pale border border-purple-accent/25 px-3 sm:px-4 py-1.5 sm:py-2 rounded-lg text-xs sm:text-sm font-medium hover:bg-purple-accent/10 hover:border-purple-accent/40 transition-all cursor-pointer"
            >
              <Users size={14} />
              <span className="hidden sm:inline">{t("community.join")}</span>
            </button>

            {/* Download button */}
            <a
              href="https://github.com/MioMioOS/MioIsland/releases"
              className="flex items-center gap-1.5 sm:gap-2 bg-green/10 text-green border border-green/20 px-3 sm:px-4 py-1.5 sm:py-2 rounded-lg text-xs sm:text-sm font-medium hover:bg-green/20 hover:border-green/30 transition-all"
            >
              <Download size={14} />
              <span className="hidden sm:inline">{t("nav.download")}</span>
            </a>
          </div>
        </div>
      </nav>

      <CommunityModal open={communityOpen} onClose={() => setCommunityOpen(false)} />
    </>
  )
}
