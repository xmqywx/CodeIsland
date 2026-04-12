import { I18nProvider } from "./lib/i18n"
import Navbar from "./components/Navbar"
import SideNav from "./components/SideNav"
import Hero from "./components/Hero"
import NotchDemo from "./components/NotchDemo"
import Features from "./components/Features"
import Plugins from "./components/Plugins"
import CodeLight from "./components/CodeLight"
import HowItWorks from "./components/HowItWorks"
import Pricing from "./components/Pricing"
import FAQ from "./components/FAQ"
import OpenSource from "./components/OpenSource"
import Footer from "./components/Footer"

function App() {
  return (
    <I18nProvider>
      <Navbar />
      <SideNav />
      <Hero />
      <NotchDemo />
      <Features />
      <Plugins />
      <CodeLight />
      <HowItWorks />
      <Pricing />
      <FAQ />
      <OpenSource />
      <Footer />
    </I18nProvider>
  )
}

export default App
