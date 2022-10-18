import { Dom } from '@brandocms/jupiter'
import slugify from 'slugify'

export default (app) => ({
  async mounted() {
    const type = this.el.dataset.slugType
    slugify.extend({ '/': '-' })

    if (this.el.dataset.slugFor) {
      let fors = []
      if (this.el.dataset.slugFor.indexOf(',') > -1) {
        fors = this.el.dataset.slugFor.split(',')      
      } else {
        fors.push(this.el.dataset.slugFor)
      }    
  
      fors.forEach(f => {
        const el = Dom.find(`[name="${f}"]`)      
        el.addEventListener('input', () => {
          const vals = fors.map(f => Dom.find(`[name="${f}"]`).value).join('-')   
          if (type === 'standard') {
            this.el.value = slugify(vals, { lower: true, strict: true })
          } else {
            this.el.value = camelCase(vals)
          }
        })
      })
    }
  }
})

function camelCase(str) {
  str = replaceAccents(str);
  str = removeNonWord(str)
    .replace(/\-/g, " ") //convert all hyphens to spaces
    .replace(/\s[a-z]/g, upperCase) //convert first char of each word to UPPERCASE
    .replace(/\s+/g, "") //remove spaces
    .replace(/^[A-Z]/g, lowerCase); //convert first char to lowercase
  return str;
}

function replaceAccents(str) {
  // verifies if the String has accents and replace them
  if (str.search(/[\xC0-\xFF]/g) > -1) {
    str = str
      .replace(/[\xC0-\xC5]/g, "A")
      .replace(/[\xC6]/g, "AE")
      .replace(/[\xC7]/g, "C")
      .replace(/[\xC8-\xCB]/g, "E")
      .replace(/[\xCC-\xCF]/g, "I")
      .replace(/[\xD0]/g, "D")
      .replace(/[\xD1]/g, "N")
      .replace(/[\xD2-\xD6\xD8]/g, "O")
      .replace(/[\xD9-\xDC]/g, "U")
      .replace(/[\xDD]/g, "Y")
      .replace(/[\xDE]/g, "P")
      .replace(/[\xE0-\xE5]/g, "a")
      .replace(/[\xE6]/g, "ae")
      .replace(/[\xE7]/g, "c")
      .replace(/[\xE8-\xEB]/g, "e")
      .replace(/[\xEC-\xEF]/g, "i")
      .replace(/[\xF1]/g, "n")
      .replace(/[\xF2-\xF6\xF8]/g, "o")
      .replace(/[\xF9-\xFC]/g, "u")
      .replace(/[\xFE]/g, "p")
      .replace(/[\xFD\xFF]/g, "y");
  }

  return str;
}

function removeNonWord(str) {
  return str.replace(/[^0-9a-zA-Z\xC0-\xFF \-]/g, "");
}

function lowerCase(str) {
  return str.toLowerCase();
}

function upperCase(str) {
  return str.toUpperCase();
}
