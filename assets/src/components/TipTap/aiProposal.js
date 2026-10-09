import { Extension } from '@tiptap/core'
import { Plugin, PluginKey } from '@tiptap/pm/state'
import { Decoration, DecorationSet } from '@tiptap/pm/view'

export const proposalKey = new PluginKey('brandoAiProposal')
export function proposalExtension({ labels, accept, discard, retry, edit }) {
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
              // The shared look for AI results waiting for review (AI.css).
              panel.className = 'tiptap-ai-proposal ai-proposal'
              panel.contentEditable = 'false'
              panel.setAttribute('role', 'region')
              panel.setAttribute('aria-label', labels.aiSuggestion)
              const title = document.createElement('span')
              title.className = 'tiptap-ai-heading ai-proposal-label'
              const icon = document.createElement('span')
              icon.className = 'lucide-sparkles'
              icon.dataset.icon = ''
              icon.setAttribute('aria-hidden', 'true')
              title.append(icon, proposal.status === 'pending' ? labels.generating : labels.aiSuggestion)
              title.setAttribute('role', 'status')
              panel.append(title)
              // A suggestion ready to accept can be changed first, as a field's
              // can (FieldActions): the textarea is outside the document, and
              // what it holds is what Accept inserts.
              if (proposal.text && proposal.status === 'ready' && !proposal.error) {
                const field = document.createElement('textarea')
                field.className = 'tiptap-ai-field ai-proposal-field'
                field.value = proposal.text
                field.rows = Math.min(Math.max(proposal.text.split('\n').length, Math.ceil(proposal.text.length / 70)), 12)
                field.setAttribute('aria-label', labels.suggestedText)
                field.addEventListener('input', () => edit?.(field.value))
                panel.append(field)
              } else if (proposal.text) { const text = document.createElement('span'); text.className = 'tiptap-ai-text'; text.textContent = proposal.text; panel.append(text) }
              if (proposal.error) { const error = document.createElement('span'); error.className = 'tiptap-ai-error'; error.setAttribute('role', 'alert'); error.textContent = proposal.error; panel.append(error) }
              const actions = document.createElement('span')
              actions.className = 'tiptap-ai-actions ai-proposal-actions'
              // Try again asks the model again, so it carries the AI mark: the
              // violet and the sparkles (AI.css).
              const button = (label, action, kind) => {
                const btn = document.createElement('button'); btn.type = 'button'
                if (kind === 'ai') { const mark = document.createElement('span'); mark.className = 'lucide-sparkles'; mark.dataset.icon = ''; mark.setAttribute('aria-hidden', 'true'); btn.append(mark) }
                btn.append(label)
                if (kind) btn.className = kind === 'ai' ? 'is-ai' : kind
                btn.addEventListener('mousedown', e => e.preventDefault()); btn.addEventListener('click', action); actions.append(btn)
              }
              if (proposal.status === 'ready' && !proposal.error) button(labels.accept, accept, 'primary')
              button(proposal.status === 'pending' ? labels.cancel : labels.discard, discard)
              if (proposal.status !== 'pending') button(labels.retry, retry, 'ai')
              panel.append(actions)
              return panel
            }, { side: 1, key: `${proposal.id}:${proposal.status}:${proposal.error || ''}`, stopEvent: () => true, ignoreSelection: true })])
          },
        },
      })]
    },
  })
}
