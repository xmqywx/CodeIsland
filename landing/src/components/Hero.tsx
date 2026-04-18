import { useState } from "react"
import { Users } from "lucide-react"
import { MacbookScroll } from "@/components/ui/macbook-scroll"
import MacScreenContent from "./MacScreenContent"
import CommunityModal from "./CommunityModal"
import { useI18n } from "../lib/i18n"
import logo from "../lib/logo"
import BlurText from "./reactbits/BlurText"
import ShinyText from "./reactbits/ShinyText"
import StarBorder from "./reactbits/StarBorder"
import LightRays from "./reactbits/LightRays"

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
        {/* LightRays background */}
        <div className="absolute inset-0 z-0 opacity-50">
          <LightRays
            raysOrigin="top-center"
            raysColor="#ffffff"
            raysSpeed={0.6}
            lightSpread={1.5}
            rayLength={2.5}
            fadeDistance={1.0}
            saturation={0.3}
            followMouse={true}
            mouseInfluence={0.05}
            noiseAmount={0.02}
            distortion={0.08}
          />
        </div>

        <MacbookScroll
          title={
            <div className="flex flex-col items-center gap-6">
              <img src={logo} alt="MioIsland" className="w-14 h-14 rounded-2xl shadow-lg" style={{ animation: 'heroEnter 1s ease-out both' }} />

              <h1 className="font-display text-4xl sm:text-5xl md:text-7xl font-extrabold tracking-tight leading-[0.95] text-center">
                <BlurText
                  text={t("hero.title1")}
                  className="text-text-primary justify-center !text-2xl sm:!text-4xl md:!text-6xl font-extrabold"
                  delay={80}
                  animateBy="letters"
                />
                <br />
                <span className="inline-flex flex-wrap justify-center">
                  <BlurText
                    text={t("hero.title2")}
                    className="text-text-primary justify-center !text-2xl sm:!text-4xl md:!text-6xl font-extrabold"
                    delay={80}
                    animateBy="letters"
                  />
                  <ShinyText
                    text={t("hero.title3")}
                    className="!text-2xl sm:!text-4xl md:!text-6xl font-extrabold"
                    color="#34d399"
                    shineColor="#6ee7b7"
                    speed={3}
                  />
                </span>
              </h1>

              <p className="text-sm sm:text-base sm:text-lg text-text-muted max-w-xl mx-auto leading-relaxed text-center px-4" style={{ animation: 'heroEnter 1s ease-out 0.6s both' }}>
                {t("hero.subtitle1")}
                <br />
                {t("hero.subtitle2")}
                <br />
                <span className="text-green/80">{t("hero.subtitle3")}</span>
              </p>

              <div className="flex flex-col sm:flex-row flex-wrap gap-3 sm:gap-4 justify-center px-4 sm:px-0" style={{ animation: 'heroEnter 1s ease-out 0.8s both' }}>
                <StarBorder
                  as="a"
                  href="https://github.com/MioMioOS/MioIsland/releases/download/v2.1.6/MioIsland-v2.1.6.dmg"
                  color="#34d399"
                  speed="4s"
                  className="!rounded-xl"
                >
                  <span className="font-mono text-sm font-bold">{t("hero.download")}</span>
                </StarBorder>
                <button
                  onClick={() => setCommunityOpen(true)}
                  className="group flex items-center justify-center gap-2.5 px-8 py-3.5 rounded-xl font-mono text-sm text-text-primary transition-all duration-300 hover:scale-[1.03] cursor-pointer"
                  style={{
                    background: "rgba(52,211,153,0.08)",
                    border: "1px solid rgba(52,211,153,0.25)",
                  }}
                >
                  <Users size={16} />
                  {t("community.join")}
                </button>
                <a
                  href="https://github.com/MioMioOS/MioIsland"
                  className="group flex items-center justify-center gap-2.5 glass px-8 py-3.5 rounded-xl font-mono text-sm text-green-bright transition-all duration-300 hover:scale-[1.03] hover:text-text-primary"
                >
                  <GithubIcon size={16} />
                  {t("hero.star")}
                </a>
              </div>
            </div>
          }
          badge={
            <a href="https://github.com/MioMioOS/MioIsland">
              <img src={logo} alt="MioIsland" className="h-10 w-10 rounded-lg -rotate-12 transform shadow-lg" />
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
