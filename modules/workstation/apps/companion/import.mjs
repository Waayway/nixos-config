// Full import of a .companionconfig into the running Companion (127.0.0.1:8000), the same
// calls the web UI's Import/Export page makes: upload in chunks, parse, then importFull.
// Replaces pages, buttons, connections, surfaces, triggers, variables and images; keeps
// the settings (userconfig). Run through `companion-import` (streamdeck.nix), which sets
// COMPANION_DIR to the Companion package so the tRPC client and ws come from there.
import fs from 'node:fs'
import crypto from 'node:crypto'

const dir = process.env.COMPANION_DIR
const { createTRPCClient, createWSClient, wsLink } = await import(`${dir}/node_modules/@trpc/client/dist/index.mjs`)
const { default: WebSocket } = await import(`${dir}/node_modules/ws/wrapper.mjs`)

const [file, url = 'ws://127.0.0.1:8000/trpc'] = process.argv.slice(2)
const data = fs.readFileSync(file)
const wsClient = createWSClient({ url, WebSocket })
const c = createTRPCClient({ links: [wsLink({ client: wsClient })] })

const up = c.importExport.prepareImport
const sessionId = await up.start.mutate({ name: file.split('/').pop(), size: data.length })
const chunk = 512 * 1024
for (let offset = 0; offset < data.length; offset += chunk)
  await up.uploadChunk.mutate({ sessionId, offset, data: data.subarray(offset, offset + chunk).toString('base64') })
const expectedChecksum = crypto.createHash('sha1').update(data).digest('hex')
const [error, info] = await up.complete.mutate({ sessionId, expectedChecksum, userData: null })
if (error) throw new Error(`Companion could not parse ${file}: ${error}`)
console.log(`connections: ${Object.values(info.connections).map((x) => x.label).join(', ')}`)
console.log(`pages: ${Object.values(info.pages ?? {}).map((p) => p.name).join(', ')}`)

const R = 'reset-and-import'
await c.importExport.importFull.mutate({
  config: {
    buttons: R,
    surfaces: { known: R, instances: R, remote: R },
    triggers: R,
    customVariables: R,
    expressionVariables: R,
    connections: 'reset',
    userconfig: 'unchanged',
    imageLibrary: R,
  },
})
// the import runs as a task after the mutation returns; give it time before closing
await new Promise((r) => setTimeout(r, 5000))
wsClient.close()
console.log('imported')
