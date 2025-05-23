<script>
  import { onMount, onDestroy } from "svelte";
  import { Editor, mergeAttributes } from "@tiptap/core";
  import StarterKit from "@tiptap/starter-kit";
  import Color from "@tiptap/extension-color";
  import TextStyle from "@tiptap/extension-text-style";
  import Typography from "@tiptap/extension-typography";
  import Subscript from "@tiptap/extension-subscript";
  import Superscript from "@tiptap/extension-superscript";
  import Link from "@tiptap/extension-link";
  import SmartText from "./extensions/SmartText";
  import Button from "./extensions/Button";
  import HTMLInputParser from "./extensions/PasteCleaner/HTMLInputParser";
  import JumpAnchor from "./extensions/JumpAnchor";
  import PreventDrop from "./extensions/PreventDrop";
  import Focus from "@tiptap/extension-focus";
  import TextAlign from "@tiptap/extension-text-align";

  import { alertPrompt } from "../../alerts";

  let { content, extensions = $bindable(), onFocus } = $props();

  let element = $state();
  let editor = $state();
  let tiptapInput;

  let isLinkActive = $state(false);
  let isH1Active = $state(false);
  let isH2Active = $state(false);
  let isH3Active = $state(false);
  let isPActive = $state(false);
  let isListActive = $state(false);
  let isButtonActive = $state(false);
  let isBoldActive = $state(false);
  let isItalicActive = $state(false);
  let isSubActive = $state(false);
  let isSupActive = $state(false);
  let isAlignLeftActive = $state(false);
  let isAlignCenterActive = $state(false);
  let isAlignRightActive = $state(false);
  let isColorActive = $state(false);
  let isJumpAnchorActive = $state(false);

  const ATTR_WHITESPACE =
    /[\u0000-\u0020\u00A0\u1680\u180E\u2000-\u2029\u205F\u3000]/g;

  const isAllowedUri = (uri, protocols) => {
    const allowedProtocols = [
      "http",
      "https",
      "ftp",
      "ftps",
      "mailto",
      "tel",
      "callto",
      "sms",
      "cid",
      "xmpp",
    ];

    if (protocols) {
      protocols.forEach((protocol) => {
        const nextProtocol =
          typeof protocol === "string" ? protocol : protocol.scheme;

        if (nextProtocol) {
          allowedProtocols.push(nextProtocol);
        }
      });
    }

    // eslint-disable-next-line no-useless-escape
    return (
      !uri ||
      uri
        .replace(ATTR_WHITESPACE, "")
        .match(
          new RegExp(
            `^(?:(?:${allowedProtocols.join("|")}):|[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$))`,
            "i",
          ),
        )
    );
  };

  const updateInput = () => {
    tiptapInput.value = editor.getHTML();
    tiptapInput.dispatchEvent(new Event("input", { bubbles: true }));
  };

  const processExtensions = () => {
    let allExtensions = [
      "p",
      "h1",
      "h2",
      "h3",
      "list",
      "link",
      "button",
      "bold",
      "italic",
      "sub",
      "sup",
      "color",
      "unsetMarks",
      "jumpAnchor",
      "smartText",
    ];

    if (extensions) {
      if (extensions === "all") {
        return allExtensions;
      }

      return extensions.split("|");
    } else {
      return allExtensions;
    }
  };

  const toggleAnchor = () => {
    let currentId = "";

    if (editor.isActive("jumpAnchor")) {
      const linkAttributes = editor.getAttributes("jumpAnchor");
      currentId = linkAttributes.id;
    }

    alertPrompt("ID/Anchor", currentId, ({ data }) => {
      if (!data) {
        editor.chain().focus().unsetJumpAnchor().run();
      } else {
        editor
          .chain()
          .focus()
          .extendMarkRange("jumpAnchor")
          .setJumpAnchor({ id: data })
          .run();
      }
    });
  };

  const toggleLink = () => {
    let currentHref = "";

    if (editor.isActive("link")) {
      const linkAttributes = editor.getAttributes("link");
      currentHref = linkAttributes.href;
    }

    alertPrompt("URL/Link", currentHref, ({ data }) => {
      if (!data) {
        editor.chain().focus().unsetLink().run();
      } else {
        let opts = { href: data };

        if (data.startsWith("/") || data.startsWith("#")) {
          opts = { ...opts, target: null, rel: null };
        }

        editor.chain().focus().extendMarkRange("link").setLink(opts).run();
      }
    });
  };

  const toggleButton = () => {
    let currentHref = "";

    if (editor.isActive("button")) {
      const buttonAttributes = editor.getAttributes("button");
      currentHref = buttonAttributes.href;
    }

    alertPrompt("URL/Link", currentHref, ({ data }) => {
      if (!data) {
        editor.chain().focus().unsetButton().run();
      } else {
        let opts = {
          href: data,
          class: "action-button",
        };

        if (data.startsWith("/") || data.startsWith("#")) {
          opts = { ...opts, target: null, rel: null };
        }

        editor.chain().focus().extendMarkRange("button").setButton(opts).run();
      }
    });
  };

  onMount(() => {
    if (!element.parentNode.parentNode) {
      return;
    }

    extensions = processExtensions();

    tiptapInput =
      element.parentNode.parentNode.parentNode.parentNode.parentNode.querySelector(
        ".tiptap-text",
      );

    const CustomLink = Link.extend({
      parseHTML() {
        return [
          {
            tag: "a[href]:not(.action-button)",
            getAttrs: (dom) => {
              const href = dom.getAttribute("href");

              // prevent XSS attacks
              if (!href || !isAllowedUri(href, this.options.protocols)) {
                return false;
              }
              return null;
            },
          },
        ];
      },
    });

    editor = new Editor({
      editorProps: {
        transformPastedHTML: (html, editorView) => {
          const htmlCleaner = new HTMLInputParser({ editorView });
          const cleanedHtml = htmlCleaner.prepareHTML(html);
          return cleanedHtml;
        },
      },
      element: element,
      extensions: [
        StarterKit.configure({
          dropcursor: false,
        }),
        Typography,

        CustomLink.configure({
          openOnClick: false,
          autolink: true,
          linkOnPaste: true,
        }),
        Subscript,
        Superscript,
        Button,
        JumpAnchor,
        Focus.configure({
          className: "has-focus",
          mode: "shallowest",
        }),
        PreventDrop,
        SmartText,
        TextStyle,
        Color,
        TextAlign.configure({ types: ["heading", "paragraph"] }),
      ],
      content,
      onFocus({ editor, event }) {
        onFocus({ editor, event });
      },
      onUpdate({ editor }) {
        updateInput();
      },
      onTransaction: () => {
        editor = editor;
        isH1Active = editor.isActive("heading", { level: 1 });
        isH2Active = editor.isActive("heading", { level: 2 });
        isH3Active = editor.isActive("heading", { level: 3 });
        isPActive = editor.isActive("paragraph");
        isListActive = editor.isActive("bulletList");
        isLinkActive = editor.isActive("link");
        isButtonActive = editor.isActive("button");
        isBoldActive = editor.isActive("bold");
        isItalicActive = editor.isActive("italic");
        isSubActive = editor.isActive("subscript");
        isSupActive = editor.isActive("superscript");
        isAlignLeftActive = editor.isActive({ textAlign: "left" });
        isAlignCenterActive = editor.isActive({ textAlign: "center" });
        isAlignRightActive = editor.isActive({ textAlign: "right" });
        isColorActive = editor.isActive("textStyle", { color: true });
        isJumpAnchorActive = editor.isActive("jumpAnchor");
      },
    });

    const handleDrop = (ev) => {
      console.log("handleDrop", ev);
    };

    element.addEventListener("drop", (ev) => {
      console.log("Svelte el got drop");
      ev.preventDefault();
      ev.stopPropagation();
      return false;
    });

    const proseMirrorEl = element.querySelector(".ProseMirror");
    proseMirrorEl.addEventListener("drop", (ev) => {
      console.log("ProseMirror el got drop");
      ev.preventDefault();
      ev.stopPropagation();
      return false;
    });
  });

  onDestroy(() => {
    if (editor) {
      editor.destroy();
    }
  });
</script>

{#if editor}
  <div class="tiptap-menu">
    {#if extensions.includes("p")}
      <button
        onclick={() => editor.chain().focus().setParagraph().run()}
        class="menu-item"
        class:active={isPActive}
        type="button"
        title="Paragraph"
        aria-label="Paragraph"
      >
        <span class="tiptap-paragraph"></span>
      </button>
    {/if}
    {#if extensions.includes("h1")}
      <button
        onclick={() => editor.chain().focus().toggleHeading({ level: 1 }).run()}
        class="menu-item"
        class:active={isH1Active}
        type="button"
        title="Heading 1"
        aria-label="Heading 1"
      >
        <span class="tiptap-h1"></span>
      </button>
    {/if}
    {#if extensions.includes("h2")}
      <button
        onclick={() => editor.chain().focus().toggleHeading({ level: 2 }).run()}
        class="menu-item"
        class:active={isH2Active}
        type="button"
        title="Heading 2"
        aria-label="Heading 2"
      >
        <span class="tiptap-h2"></span>
      </button>
    {/if}
    {#if extensions.includes("h3")}
      <button
        onclick={() => editor.chain().focus().toggleHeading({ level: 3 }).run()}
        class="menu-item"
        class:active={isH3Active}
        type="button"
        title="Heading 3"
        aria-label="Heading 3"
      >
        <span class="tiptap-h3"></span>
      </button>
    {/if}
    {#if extensions.includes("list")}
      <button
        onclick={() => editor.chain().focus().toggleBulletList().run()}
        class="menu-item"
        class:active={isListActive}
        type="button"
        title="Bullet list"
        aria-label="Bullet list"
      >
        <span class="hero-list-bullet"></span>
      </button>
    {/if}
    {#if extensions.includes("link")}
      <button
        onclick={() => toggleLink()}
        type="button"
        title="Link"
        class="menu-item"
        class:active={isLinkActive}
        aria-label="Link"
      >
        <span class="hero-link"></span>
      </button>
    {/if}
    {#if extensions.includes("button") || extensions.includes("action_button")}
      <button
        onclick={() => toggleButton()}
        type="button"
        title="Button"
        class="menu-item"
        class:active={isButtonActive}
        aria-label="Button"
      >
        <span class="hero-squares-plus"></span>
      </button>
    {/if}
    {#if extensions.includes("bold")}
      <button
        onclick={() => editor.chain().focus().toggleBold().run()}
        class="menu-item"
        class:active={isBoldActive}
        type="button"
        title="Bold"
        aria-label="Bold"
      >
        <span class="tiptap-bold"></span>
      </button>
    {/if}
    {#if extensions.includes("italic")}
      <button
        onclick={() => editor.chain().focus().toggleItalic().run()}
        class="menu-item"
        class:active={isItalicActive}
        type="button"
        title="Italic"
        aria-label="Italic"
      >
        <span class="tiptap-italic"></span>
      </button>
    {/if}
    {#if extensions.includes("sub")}
      <button
        onclick={() => editor.chain().focus().toggleSubscript().run()}
        class="menu-item"
        class:active={isSubActive}
        type="button"
        title="Subscript"
        aria-label="Subscript"
      >
        <span class="tiptap-sub"></span>
      </button>
    {/if}
    {#if extensions.includes("sup")}
      <button
        onclick={() => editor.chain().focus().toggleSuperscript().run()}
        class="menu-item"
        class:active={isSupActive}
        type="button"
        title="Superscript"
        aria-label="Superscript"
      >
        <span class="tiptap-sup"></span>
      </button>
    {/if}
    {#if extensions.includes("align")}
      <button
        onclick={() => editor.chain().focus().setTextAlign("left").run()}
        class="menu-item"
        class:active={isAlignLeftActive}
        type="button"
        title="Align left"
        aria-label="Align left"
      >
        <span class="hero-bars-3-bottom-left"></span>
      </button>
      <button
        onclick={() => editor.chain().focus().setTextAlign("center").run()}
        class="menu-item"
        class:active={isAlignCenterActive}
        type="button"
        title="Align center"
        aria-label="Align center"
      >
        <span class="hero-bars-3"></span>
      </button>
      <button
        onclick={() => editor.chain().focus().setTextAlign("right").run()}
        class="menu-item"
        class:active={isAlignRightActive}
        type="button"
        title="Align right"
        aria-label="Align right"
      >
        <span class="hero-bars-3-bottom-right"></span>
      </button>
    {/if}
    {#if extensions.includes("color")}
      <label class="menu-item">
        <span class="hero-swatch"></span>

        <input
          type="color"
          class:active={isColorActive}
          oninput={(ev) =>
            editor.chain().focus().setColor(ev.target.value).run()}
          value={editor.getAttributes("textStyle").color}
        />
      </label>
    {/if}
    {#if extensions.includes("jumpAnchor")}
      <button
        onclick={() => toggleAnchor()}
        class="menu-item"
        type="button"
        title="Jump anchor"
        class:active={isJumpAnchorActive}
        aria-label="Jump anchor"
      >
        <span class="tiptap-anchor"></span>
      </button>
    {/if}
    <button
      onclick={() => editor.chain().focus().unsetAllMarks().run()}
      class="menu-item"
      type="button"
      title="Clear marks"
      aria-label="Clear marks"
    >
      <span class="tiptap-clear"></span>
    </button>
  </div>
{/if}

<div bind:this={element}></div>
