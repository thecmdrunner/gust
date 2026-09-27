import { mkdirSync, cpSync, readdirSync } from 'node:fs'
import { resolve } from 'node:path'
const root = resolve(import.meta.dir, '../..')
process.chdir(root)
export function run(args: string[]) {
  const p = Bun.spawnSync(args, { stdout: 'inherit', stderr: 'inherit' })
  if (p.exitCode !== 0) throw new Error(`${args[0]} failed (${p.exitCode ?? p.signalCode})`)
}
const universal = !process.argv.includes('--host-only')
const architectures = universal ? ['arm64', 'x86_64'] : [process.arch === 'arm64' ? 'arm64' : 'x86_64']
for (const arch of architectures) {
  const dir = `app/build/direct-${arch}`
  mkdirSync(dir, { recursive: true })
  const target = `${arch}-apple-macosx13.0`
  run(['xcrun', 'clang', '-target', target, '-O2', '-Wall', '-I', 'app/Sources/CSMC/include', '-c', 'app/Sources/CSMC/CSMC.c', '-o', `${dir}/CSMC.o`])
  run(['xcrun', 'swiftc', '-target', target, '-swift-version', '5', '-O', '-I', 'app/Sources/CSMC/include', '-emit-library', '-static', '-emit-module', '-module-name', 'GustCore', 'app/Sources/GustCore/SMC.swift', 'app/Sources/GustCore/Temperature.swift', '-emit-module-path', `${dir}/GustCore.swiftmodule`, '-o', `${dir}/libGustCore.a`])
  for (const name of ['GustHelper', 'Gust']) {
    const sources = readdirSync(`app/Sources/${name}`).filter(f => f.endsWith('.swift')).sort().map(f => `app/Sources/${name}/${f}`)
    run(['xcrun', 'swiftc', '-target', target, '-swift-version', '5', '-O', '-I', 'app/Sources/CSMC/include', '-I', dir, '-L', dir, '-lGustCore', '-framework', 'IOKit', `${dir}/CSMC.o`, ...sources, '-o', `${dir}/${name}`])
  }
}
const bundle = process.env.GUST_APP_BUNDLE || 'app/build/Gust.app'
const app = `${bundle}/Contents`
mkdirSync(`${app}/MacOS`, { recursive: true })
mkdirSync(`${app}/Helpers`, { recursive: true })
mkdirSync(`${app}/Resources`, { recursive: true })
for (const [name, destination] of [['Gust', 'MacOS'], ['GustHelper', 'Helpers']]) {
  const paths = architectures.map(a => `app/build/direct-${a}/${name}`)
  if (universal) run(['lipo', '-create', ...paths, '-output', `${app}/${destination}/${name}`])
  else cpSync(paths[0], `${app}/${destination}/${name}`)
}
cpSync('app/Resources/Info.plist', `${app}/Info.plist`)
// SIGN_IDENTITY may be set when a Developer ID certificate is available.
const identity = process.env.SIGN_IDENTITY || '-'
const options = identity === '-' ? [] : ['--options', 'runtime', '--timestamp']
cpSync('app/Resources/AppIcon.icns', `${app}/Resources/AppIcon.icns`)
cpSync('LICENSE', `${app}/Resources/LICENSE`)
cpSync('app/Resources/ThirdPartyNotices.txt', `${app}/Resources/ThirdPartyNotices.txt`)
run(['codesign', '--force', '--sign', identity, ...options, `${app}/Helpers/GustHelper`])
run(['codesign', '--force', '--sign', identity, ...options, bundle])
run(['codesign', '--verify', '--deep', '--strict', bundle])
console.log(`Built ${bundle}`)
