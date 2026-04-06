import { useState } from "react"
import { Users } from "lucide-react"
import { MacbookScroll } from "@/components/ui/macbook-scroll"
import MacScreenContent from "./MacScreenContent"
import CommunityModal from "./CommunityModal"
import { useI18n } from "../lib/i18n"
import logo from "../lib/logo"

const GithubIcon = ({ size = 16 }: { size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor">
    <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
  </svg>
)

export default function Hero() {
  const { t } = useI18n()
  const [communityOpen, setCommunityOpen] = useState(false)

  return (
    <>
      <div className="w-full bg-deep relative z-10 isolate">
        <MacbookScroll
          title={
            <div className="flex flex-col items-center gap-6">
              <img src={logo} alt="CodeIsland" className="w-14 h-14 rounded-2xl shadow-lg" style={{ animation: 'heroEnter 1s ease-out both' }} />

              <h1 className="font-display text-4xl sm:text-5xl md:text-7xl font-extrabold tracking-tight leading-[0.95] text-center" style={{ animation: 'heroEnter 1s ease-out 0.1s both' }}>
                <span className="text-text-primary">{t("hero.title1")}</span>
                <br />
                <span className="text-text-primary">{t("hero.title2")}</span>
                <span
                  className="text-transparent bg-clip-text"
                  style={{
                    backgroundImage: 'linear-gradient(135deg, #34d399, #6ee7b7, #a78bfa)',
                    backgroundSize: '200% 200%',
                    animation: 'gradient-shift 5s ease-in-out infinite',
                  }}
                >
                  {t("hero.title3")}
                </span>
              </h1>

              <p className="text-sm sm:text-base sm:text-lg text-text-muted max-w-xl mx-auto leading-relaxed text-center px-4" style={{ animation: 'heroEnter 1s ease-out 0.2s both' }}>
                {t("hero.subtitle1")}
                <br />
                {t("hero.subtitle2")}
              </p>

              <div className="flex flex-col sm:flex-row flex-wrap gap-3 sm:gap-4 justify-center px-4 sm:px-0" style={{ animation: 'heroEnter 1s ease-out 0.3s both' }}>
                <a
                  href="https://github.com/xmqywx/CodeIsland/releases"
                  className="group flex items-center justify-center gap-2.5 bg-green text-deep px-8 py-3.5 rounded-xl font-mono text-sm font-bold transition-all duration-300 hover:shadow-[0_0_40px_rgba(52,211,153,0.3)] hover:scale-[1.03]"
                >
                  {t("hero.download")}
                </a>
                <button
                  onClick={() => setCommunityOpen(true)}
                  className="group flex items-center justify-center gap-2.5 px-8 py-3.5 rounded-xl font-mono text-sm text-text-primary transition-all duration-300 hover:scale-[1.03] cursor-pointer"
                  style={{
                    background: "linear-gradient(135deg, rgba(124,58,237,0.15) 0%, rgba(52,211,153,0.15) 100%)",
                    border: "1px solid rgba(124,58,237,0.3)",
                  }}
                >
                  <Users size={16} />
                  {t("community.join")}
                </button>
                <a
                  href="https://github.com/xmqywx/CodeIsland"
                  className="group flex items-center justify-center gap-2.5 glass px-8 py-3.5 rounded-xl font-mono text-sm text-purple-pale transition-all duration-300 hover:scale-[1.03] hover:text-text-primary"
                >
                  <GithubIcon size={16} />
                  {t("hero.star")}
                </a>
              </div>
            </div>
          }
          badge={
            <a href="https://github.com/xmqywx/CodeIsland">
              <img src={logo} alt="CodeIsland" className="h-10 w-10 rounded-lg -rotate-12 transform shadow-lg" />
            </a>
          }
          screenContent={<MacScreenContent />}
          showGradient={false}
        />
      </div>

      <CommunityModal open={communityOpen} onClose={() => setCommunityOpen(false)} />
    </>
  )
}
