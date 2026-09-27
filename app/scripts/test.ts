import { resolve } from 'node:path'
process.chdir(resolve(import.meta.dir, '../..'))
const dir = `app/build/direct-${process.arch === 'arm64' ? 'arm64' : 'x86_64'}`
for (const args of [
  ['xcrun', 'swiftc', '-swift-version', '5', '-I', 'app/Sources/CSMC/include', '-I', dir, '-L', dir, '-lGustCore', '-framework', 'IOKit', `${dir}/CSMC.o`, 'app/Tests/GustCoreTests/main.swift', '-o', `${dir}/GustCoreTests`],
  [`${dir}/GustCoreTests`]
]) {
  const p = Bun.spawnSync(args, { stdout: 'inherit', stderr: 'inherit' })
  if (p.exitCode) process.exit(p.exitCode)
}
