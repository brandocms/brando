<script>
  import { onMount, onDestroy } from 'svelte'
  import { Editor } from '@tiptap/core'
  import StarterKit from '@tiptap/starter-kit'
  import Typography from '@tiptap/extension-typography'
  import Link from '@tiptap/extension-link'
  import Button from './extensions/Button'
  import Variable from './extensions/Variable'
  import PreventDrop from './extensions/PreventDrop'
  import Focus from '@tiptap/extension-focus'

  export let content
  let element
  let editor
  let tiptapInput

  const updateInput = () => {
    tiptapInput.value = editor.getHTML()
    tiptapInput.dispatchEvent(new Event('input', { bubbles: true }))
  }

  const showSchema = () => {}

  onMount(() => {
    if (!element.parentNode.parentNode) {
      return
    }
    
    tiptapInput = element.parentNode.parentNode.querySelector('.tiptap-text')

    editor = new Editor({
      element: element,
      extensions: [        
        StarterKit.configure({
          dropcursor: false
        }),
        Typography,
        Link.configure({
          openOnClick: false
        }),
        Button,
        Variable,
        Focus.configure({
          className: 'has-focus',
          mode: 'shallowest',
        }),
        PreventDrop
      ],
      content,
      onUpdate({ editor }) {
        updateInput()
      },
      onTransaction: () => {
        // force re-render so `editor.isActive` works as expected
        editor = editor
      },
    })

    const handleDrop = ev => {
      console.log('handleDrop', ev)
    }

    element.addEventListener('drop', ev => {
      console.log('Svelte el got drop')
      ev.preventDefault()
      ev.stopPropagation()
      return false
    })

    const proseMirrorEl = element.querySelector('.ProseMirror')
    proseMirrorEl.addEventListener('drop', ev => {
      console.log('ProseMirror el got drop')
      ev.preventDefault()
      ev.stopPropagation()
      return false
    })
  })

  onDestroy(() => {
    if (editor) {
      editor.destroy()
    }
  })
</script>

{#if editor}
  <div class="tiptap-menu">
    <button 
      on:click={() => editor.chain().focus().setParagraph().run()}
      class="menu-item"
      class:active={editor.isActive('paragraph')}
      type="button"
      title="Paragraph">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 6v15h-2v-5a6 6 0 1 1 0-12h10v2h-3v15h-2V6h-3zm-2 0a4 4 0 1 0 0 8V6z" fill="rgba(0,0,0,1)"/></svg>
    </button>
    <button 
      on:click={() => editor.chain().focus().toggleHeading({ level: 1}).run()}
      class="menu-item"
      class:active={editor.isActive('heading', { level: 1 })}
      type="button"
      title="Heading 1">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0H24V24H0z"/><path d="M13 20h-2v-7H4v7H2V4h2v7h7V4h2v16zm8-12v12h-2v-9.796l-2 .536V8.67L19.5 8H21z"/></svg>
    </button>
    <button 
      on:click={() => editor.chain().focus().toggleHeading({ level: 2}).run()}
      class="menu-item"
      class:active={editor.isActive('heading', { level: 2 })}
      type="button"
      title="Heading 2">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0H24V24H0z"/><path d="M4 4v7h7V4h2v16h-2v-7H4v7H2V4h2zm14.5 4c2.071 0 3.75 1.679 3.75 3.75 0 .857-.288 1.648-.772 2.28l-.148.18L18.034 18H22v2h-7v-1.556l4.82-5.546c.268-.307.43-.709.43-1.148 0-.966-.784-1.75-1.75-1.75-.918 0-1.671.707-1.744 1.606l-.006.144h-2C14.75 9.679 16.429 8 18.5 8z"/></svg>
    </button>
    <button  
      on:click={() => editor.chain().focus().toggleHeading({ level: 3 }).run()}
      class="menu-item"
      class:active={editor.isActive('heading', { level: 3 })}
      type="button"
      title="Heading 3">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0H24V24H0z"/><path d="M22 8l-.002 2-2.505 2.883c1.59.435 2.757 1.89 2.757 3.617 0 2.071-1.679 3.75-3.75 3.75-1.826 0-3.347-1.305-3.682-3.033l1.964-.382c.156.806.866 1.415 1.718 1.415.966 0 1.75-.784 1.75-1.75s-.784-1.75-1.75-1.75c-.286 0-.556.069-.794.19l-1.307-1.547L19.35 10H15V8h7zM4 4v7h7V4h2v16h-2v-7H4v7H2V4h2z"/></svg>
    </button>

    <button 
      on:click={() => editor.chain().focus().toggleBulletList().run()}
      class="menu-item"
      class:active={editor.isActive('bulletList')}
      type="button"
      title="Bullet list">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M8 4h13v2H8V4zM4.5 6.5a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zm0 7a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zm0 6.9a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zM8 11h13v2H8v-2zm0 7h13v2H8v-2z"/></svg>
    </button>

    <button type="button" title="Link" class="menu-item" data-command="link" :on-click="show_link_modal" phx-value-id={"#{v(@block, :uid)}-link"}>
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M17.657 14.828l-1.414-1.414L17.657 12A4 4 0 1 0 12 6.343l-1.414 1.414-1.414-1.414 1.414-1.414a6 6 0 0 1 8.485 8.485l-1.414 1.414zm-2.829 2.829l-1.414 1.414a6 6 0 1 1-8.485-8.485l1.414-1.414 1.414 1.414L6.343 12A4 4 0 1 0 12 17.657l1.414-1.414 1.414 1.414zm0-9.9l1.415 1.415-7.071 7.07-1.415-1.414 7.071-7.07z"/></svg>
    </button>

    <button 
      on:click={() => showSchema()}
      type="button" 
      title="Button" 
      class="menu-item" >
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M4 3h16a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zm1 2v14h14V5H5z"/></svg>
    </button>

    <button 
      on:click={() => editor.chain().focus().toggleBold().run()}
      class="menu-item"
      class:active={editor.isActive('bold')}
      type="button"
      title="Bold">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M8 11h4.5a2.5 2.5 0 1 0 0-5H8v5zm10 4.5a4.5 4.5 0 0 1-4.5 4.5H6V4h6.5a4.5 4.5 0 0 1 3.256 7.606A4.498 4.498 0 0 1 18 15.5zM8 13v5h5.5a2.5 2.5 0 1 0 0-5H8z" fill="rgba(0,0,0,1)"/></svg>
    </button>
    <button 
      on:click={() => editor.chain().focus().toggleItalic().run()}
      class="menu-item"
      class:active={editor.isActive('italic')}
      type="button"
      title="Italic">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M15 20H7v-2h2.927l2.116-12H9V4h8v2h-2.927l-2.116 12H15z" fill="rgba(0,0,0,1)"/></svg>
    </button>
  </div>
{/if}

<div bind:this={element} />

<style>
  button.active {
    background: black;
    color: white;
  }
</style>