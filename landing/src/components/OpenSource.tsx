import { useEffect, useState } from "react"
import { GitFork, Star, Heart } from "lucide-react"
import { useI18n } from "../lib/i18n"

const GithubIcon = ({ size = 16 }: { size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor">
    <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
  </svg>
)

const REPO = "MioMioOS/MioIsland"

function useGitHubStats() {
  const [stats, setStats] = useState({ stars: 0, forks: 0, contributors: 0 })
  useEffect(() => {
    fetch(`https://api.github.com/repos/${REPO}`).then(r => r.json()).then(d => {
      setStats(prev => ({ ...prev, stars: d.stargazers_count ?? 0, forks: d.forks_count ?? 0 }))
    }).catch(() => {})
    fetch(`https://api.github.com/repos/${REPO}/contributors?per_page=100`).then(r => r.json()).then(d => {
      if (Array.isArray(d)) setStats(prev => ({ ...prev, contributors: d.length }))
    }).catch(() => {})
  }, [])
  return stats
}

export default function OpenSource() {
  const { stars, forks, contributors } = useGitHubStats()
  const { t } = useI18n()

  return (
    <section id="open-source" className="relative z-20 bg-deep py-20 sm:py-32 px-4 sm:px-6 noise overflow-hidden">
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_60%_40%_at_50%_50%,rgba(124,58,237,0.06)_0%,transparent_70%)]" />
      <div className="max-w-3xl mx-auto text-center relative z-10">
        <div style={{ animation: 'heroEnter 0.8s ease-out both' }}>
          <pre className="font-mono text-sm text-green leading-snug inline-block mb-8 font-bold glow-green select-none">
{`   +====+
   | CC |
   +====+
    |||
~~~~|||~~~~`}
          </pre>
          <h2 className="font-display text-3xl sm:text-4xl sm:text-5xl font-extrabold text-text-primary">{t("os.title")}</h2>
          <p className="text-sm sm:text-base text-text-muted mt-4 max-w-lg mx-auto leading-relaxed px-4">{t("os.desc")}</p>
        </div>

        <div style={{ animation: 'heroEnter 0.8s ease-out 0.1s both' }} className="flex flex-wrap justify-center gap-3 sm:gap-4 mt-10">
          <a href={`https://github.com/${REPO}/stargazers`} className="glass rounded-xl px-4 sm:px-6 py-3 flex items-center gap-2 transition-all hover:scale-105">
            <Star size={14} className="text-amber" />
            <span className="font-mono text-sm text-text-primary font-bold">{stars}</span>
            <span className="font-mono text-xs text-text-muted">Stars</span>
          </a>
          <a href={`https://github.com/${REPO}/forks`} className="glass rounded-xl px-4 sm:px-6 py-3 flex items-center gap-2 transition-all hover:scale-105">
            <GitFork size={14} className="text-purple-light" />
            <span className="font-mono text-sm text-text-primary font-bold">{forks}</span>
            <span className="font-mono text-xs text-text-muted">Forks</span>
          </a>
          <a href={`https://github.com/${REPO}/graphs/contributors`} className="glass rounded-xl px-4 sm:px-6 py-3 flex items-center gap-2 transition-all hover:scale-105">
            <Heart size={14} className="text-red-400" />
            <span className="font-mono text-sm text-text-primary font-bold">{contributors}</span>
            <span className="font-mono text-xs text-text-muted">{t("os.contributors")}</span>
          </a>
        </div>

        <div style={{ animation: 'heroEnter 0.8s ease-out 0.2s both' }} className="flex flex-col sm:flex-row flex-wrap justify-center gap-3 sm:gap-4 mt-10 px-4 sm:px-0">
          <a href={`https://github.com/${REPO}`} className="flex items-center justify-center gap-2.5 bg-green text-deep px-8 py-3.5 rounded-xl font-mono text-sm font-bold transition-all duration-300 hover:shadow-[0_0_40px_rgba(52,211,153,0.3)] hover:scale-105">
            <GitFork size={16} />{t("os.fork")}
          </a>
          <a href={`https://github.com/${REPO}#readme`} className="flex items-center justify-center gap-2.5 glass px-8 py-3.5 rounded-xl font-mono text-sm text-purple-pale transition-all duration-300 hover:scale-105 hover:text-text-primary">
            <GithubIcon size={16} />{t("os.docs")}
          </a>
        </div>
      </div>
    </section>
  )
}
