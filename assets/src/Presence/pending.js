import pendingInputs from './pendingInputs'

// The page's one record of what this editor is typing into block inputs
// (`pendingInputs.js`), shared by the LiveSocket's patch callbacks and the
// block hook.
export default pendingInputs()
