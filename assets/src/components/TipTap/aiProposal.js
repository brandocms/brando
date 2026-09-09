import { Extension } from '@tiptap/core'
import { Plugin, PluginKey } from '@tiptap/pm/state'
import { Decoration, DecorationSet } from '@tiptap/pm/view'

export const proposalKey = new PluginKey('brandoAiProposal')
export function proposalExtension({ labels, accept, discard, retry }) {
  return Extension.create({
    name: 'aiProposal',
    addProseMirrorPlugins() {
      return [new Plugin({
        key: proposalKey,
        state: {
          init: () => null,
          apply: (tr, current) => tr.getMeta(proposalKey) !== undefined ? tr.getMeta(proposalKey) : current ? { ...current, pos: tr.mapping.map(current.pos) } : null,
        },
        props: {
          decorations(state) {
            const proposal = proposalKey.getState(state)
            if (!proposal) return DecorationSet.empty
            return DecorationSet.create(state.doc, [Decoration.widget(proposal.pos, () => {
              const panel = document.createElement('span')
              panel.className = 'tiptap-ai-proposal'
              panel.contentEditable = 'false'
              panel.setAttribute('role', 'region')
              panel.setAttribute('aria-label', labels.aiSuggestion)
              const title = document.createElement('span')
              title.className = 'tiptap-ai-heading'
              title.textContent = proposal.status === 'pending' ? labels.generating : labels.aiSuggestion
              title.setAttribute('role', 'status')
              panel.append(title)
              if (proposal.text) { const text = document.createElement('span'); text.className = 'tiptap-ai-text'; text.textContent = proposal.text; panel.append(text) }
              if (proposal.error) { const error = document.createElement('span'); error.className = 'tiptap-ai-error'; error.setAttribute('role', 'alert'); error.textContent = proposal.error; panel.append(error) }
              const actions = document.createElement('span')
              actions.className = 'tiptap-ai-actions'
              const button = (label, action, primary = false) => { const btn = document.createElement('button'); btn.type = 'button'; btn.textContent = label; btn.className = primary ? 'primary' : 'secondary'; btn.addEventListener('mousedown', e => e.preventDefault()); btn.addEventListener('click', action); actions.append(btn) }
              if (proposal.status === 'ready' && !proposal.error) button(labels.accept, accept, true)
              button(proposal.status === 'pending' ? labels.cancel : labels.discard, discard)
              if (proposal.status !== 'pending') button(labels.retry, retry)
              panel.append(actions)
              return panel
            }, { side: 1, key: `${proposal.id}:${proposal.status}:${proposal.error || ''}`, stopEvent: () => true, ignoreSelection: true })])
          },
        },
      })]
    },
  })
}
