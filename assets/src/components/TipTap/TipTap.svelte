<script>
  import { onMount, onDestroy } from 'svelte'
  import { Editor } from '@tiptap/core'
  import StarterKit from '@tiptap/starter-kit'
  import Color from '@tiptap/extension-color'
  import TextStyle from '@tiptap/extension-text-style'
  import Typography from '@tiptap/extension-typography'
  import Subscript from '@tiptap/extension-subscript'
  import Superscript from '@tiptap/extension-superscript'
  import Link from './extensions/Link'
  import Button from './extensions/Button'
  import JumpAnchor from './extensions/JumpAnchor'
  import PreventDrop from './extensions/PreventDrop'
  import Focus from '@tiptap/extension-focus'

  import { alertPrompt } from '../../alerts'

  export let content
  export let extensions
  
  let element
  let editor
  let tiptapInput

  const updateInput = () => {
    tiptapInput.value = editor.getHTML()
    tiptapInput.dispatchEvent(new Event('input', { bubbles: true }))
  }

  const processExtensions = () => {
    let allExtensions = [
      'p',
      'h1',
      'h2',
      'h3',
      'list',
      'link',
      'button',
      'bold',
      'italic',
      'sub',
      'sup',
      'color',
      'unsetMarks',
      'jumpAnchor'
    ]

    if (extensions) {
      if (extensions === 'all') {
        return allExtensions
      }

      return extensions.split('|')
    } else {
      return allExtensions
    }
  }

  const toggleAnchor = () => {
    let currentId = ''

    if (editor.isActive('jumpAnchor')) {
      const linkAttributes = editor.getAttributes('jumpAnchor')
      currentId = linkAttributes.id
    }

    alertPrompt('ID/Anchor', currentId, ({ data }) => {
      if (!data) {
        editor.chain().focus().unsetJumpAnchor().run()
      } else {
        editor
          .chain()
          .focus()
          .extendMarkRange('jumpAnchor')
          .setJumpAnchor({ id: data })
          .run()
      }
    })
  }

  const toggleLink = () => {
    let currentHref = ''

    if (editor.isActive('link')) {
      const linkAttributes = editor.getAttributes('link')
      currentHref = linkAttributes.href
    }

    alertPrompt('URL/Link', currentHref, ({ data }) => {
      if (!data) {
        editor.chain().focus().unsetLink().run()
      } else {
        editor
          .chain()
          .focus()
          .extendMarkRange('link')
          .setLink({ href: data })
          .run()
      }
    })
  }

  const toggleButton = () => {
    let currentHref = ''

    if (editor.isActive('button')) {
      const buttonAttributes = editor.getAttributes('button')
      currentHref = buttonAttributes.href
    }

    alertPrompt('URL/Link', currentHref, ({ data }) => {
      if (!data) {
        editor.chain().focus().unsetButton().run()
      } else {
        editor
          .chain()
          .focus()
          .extendMarkRange('button')
          .setButton({ href: data })
          .run()
      }
    })
  }

  onMount(() => {
    if (!element.parentNode.parentNode) {
      return
    }

    extensions = processExtensions()
    tiptapInput = element.parentNode.parentNode.parentNode.parentNode.parentNode.querySelector('.tiptap-text')

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
        Subscript,
        Superscript,
        Button,
        JumpAnchor,
        Focus.configure({
          className: 'has-focus',
          mode: 'shallowest',
        }),
        PreventDrop,
        TextStyle,
        Color
      ],
      content,
      onUpdate({ editor }) {
        updateInput()
      },
      onTransaction: () => {
        // if (editor.options.element.clientHeight > document.body.clientHeight) {
        //   editor.options.element.classList.add('pinned')
        // } else {
        //   editor.options.element.classList.remove('pinned')
        // }
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
    {#if extensions.includes('p')}
      <button 
        on:click={() => editor.chain().focus().setParagraph().run()}
        class="menu-item"
        class:active={editor.isActive('paragraph')}
        type="button"
        title="Paragraph">
        <span class="tiptap-paragraph"></span>
      </button>
    {/if}
    {#if extensions.includes('h1')}
      <button 
        on:click={() => editor.chain().focus().toggleHeading({ level: 1}).run()}
        class="menu-item"
        class:active={editor.isActive('heading', { level: 1 })}
        type="button"
        title="Heading 1">        
        <span class="tiptap-h1"></span>
      </button>
    {/if}
    {#if extensions.includes('h2')}
      <button 
        on:click={() => editor.chain().focus().toggleHeading({ level: 2}).run()}
        class="menu-item"
        class:active={editor.isActive('heading', { level: 2 })}
        type="button"
        title="Heading 2">        
        <span class="tiptap-h2"></span>
      </button>
    {/if}
    {#if extensions.includes('h3')}
      <button  
        on:click={() => editor.chain().focus().toggleHeading({ level: 3 }).run()}
        class="menu-item"
        class:active={editor.isActive('heading', { level: 3 })}
        type="button"
        title="Heading 3">
        <span class="tiptap-h3"></span>
      </button>
    {/if}
    {#if extensions.includes('list')}
      <button 
        on:click={() => editor.chain().focus().toggleBulletList().run()}
        class="menu-item"
        class:active={editor.isActive('bulletList')}
        type="button"
        title="Bullet list">
        <span class="hero-list-bullet"></span>
      </button>
    {/if}
    {#if extensions.includes('link')}
      <button 
        on:click={() => toggleLink()}
        type="button" 
        title="Link" 
        class="menu-item" 
        class:active={editor.isActive('link')}>
        <span class="hero-link"></span>
      </button>
    {/if}
    {#if extensions.includes('button') || extensions.includes('action_button')}
      <button 
        on:click={() => toggleButton()}
        type="button" 
        title="Link" 
        class="menu-item" 
        class:active={editor.isActive('button')}>
        <span class="hero-squares-plus"></span>
      </button>
    {/if}
    {#if extensions.includes('bold')}
      <button 
        on:click={() => editor.chain().focus().toggleBold().run()}
        class="menu-item"
        class:active={editor.isActive('bold')}
        type="button"
        title="Bold">
        <span class="tiptap-bold"></span>
      </button>
    {/if}
    {#if extensions.includes('italic')}
      <button 
        on:click={() => editor.chain().focus().toggleItalic().run()}
        class="menu-item"
        class:active={editor.isActive('italic')}
        type="button"
        title="Italic">
        <span class="tiptap-italic"></span>
      </button>
    {/if}
    {#if extensions.includes('sub')}
      <button 
        on:click={() => editor.chain().focus().toggleSubscript().run()}
        class="menu-item"
        class:active={editor.isActive('subscript')}
        type="button"
        title="Subscript">
        <span class="tiptap-sub"></span>
      </button>
      {/if}
      {#if extensions.includes('sup')}
      <button 
      on:click={() => editor.chain().focus().toggleSuperscript().run()}
      class="menu-item"
      class:active={editor.isActive('superscript')}
      type="button"
      title="Superscript">
        <span class="tiptap-sup"></span>        
      </button>
    {/if}
    {#if extensions.includes('color')}
      <label class="menu-item">
        <span class="hero-swatch"></span>

        <input
          type="color"
          on:input={ev => editor.chain().focus().setColor(ev.target.value).run()}
          value={editor.getAttributes('textStyle').color}>
      </label>
    {/if}
    {#if extensions.includes('jumpAnchor')}
    <button 
      on:click={() => toggleAnchor()}
      class="menu-item"
      type="button"
      title="Jump anchor"
      class:active={editor.isActive('jumpAnchor')}>
      <span class="tiptap-anchor"></span>
    </button>
    {/if}
    <button 
      on:click={() => editor.chain().focus().unsetAllMarks().run()}
      class="menu-item"
      type="button"
      title="Clear marks">
      <span class="tiptap-clear"></span>
    </button>
  </div>
  {/if}
  
  <div bind:this={element} />
