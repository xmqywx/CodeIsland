import Dock from "./reactbits/Dock"
import type { DockItemData } from "./reactbits/Dock"
import { Monitor, Zap, Puzzle, Smartphone, Rocket, DollarSign, HelpCircle, GitBranch } from "lucide-react"
import { useI18n } from "../lib/i18n"

export default function SideNav() {
  const { t } = useI18n()

  const scrollTo = (id: string) => {
    document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" })
  }

  const items: DockItemData[] = [
    {
      icon: <Monitor size={18} className="text-white" />,
      label: t("nav.demo" as any),
      onClick: () => scrollTo("demo"),
    },
    {
      icon: <Zap size={18} className="text-white" />,
      label: t("nav.features" as any),
      onClick: () => scrollTo("features"),
    },
    {
      icon: <Puzzle size={18} className="text-white" />,
      label: t("sidenav.plugins" as any),
      onClick: () => scrollTo("plugins"),
    },
    {
      icon: <Smartphone size={18} className="text-white" />,
      label: t("sidenav.codelight" as any),
      onClick: () => scrollTo("codelight"),
    },
    {
      icon: <Rocket size={18} className="text-white" />,
      label: t("nav.howItWorks" as any),
      onClick: () => scrollTo("how-it-works"),
    },
    {
      icon: <DollarSign size={18} className="text-white" />,
      label: t("sidenav.pricing" as any),
      onClick: () => scrollTo("pricing"),
    },
    {
      icon: <HelpCircle size={18} className="text-white" />,
      label: t("sidenav.faq" as any),
      onClick: () => scrollTo("faq"),
    },
    {
      icon: <GitBranch size={18} className="text-white" />,
      label: t("sidenav.opensource" as any),
      onClick: () => scrollTo("open-source"),
    },
  ]

  return (
    <div className="fixed bottom-4 left-1/2 -translate-x-1/2 z-50 hidden lg:block">
      <Dock items={items} magnification={60} baseItemSize={40} panelHeight={56} />
    </div>
  )
}
