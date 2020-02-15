class JobRunner {
  constructor() {
    const channel = btoa(window.location.pathname.split("/").pop())
      , socketProtocol = location.protocol === "https:" ? "wss:" : "ws:"
    this.channelURI = socketProtocol + "//" + window.location.host + "/socket?channel=" + channel
    this.editors = {}
  }

  connect() {
    this.ws = new WebSocket(this.channelURI)
    this.ws.onclose = this.onclose.bind(this)
    this.ws.onopen  = this.onopen.bind(this)
    this.ws.onmessage = this.onmessage.bind(this)
    this.ws.onerror = this.onerror.bind(this)

    return this
  }

  reconnect() {
    console.log("Will retry in 5s")
    setTimeout(() => {
      this.connect()
    }, 5000)
  }

  send(cmd) {
    this.ws.send(JSON.stringify(cmd))
  }

  onclose(e) {
    console.log("Websocket is closed", e)
    if (e.code <= 1016) {
      this.route({type: "close"})
      this.reconnect()
    }
  }

  onopen(e) {
    console.log("Websocket connection is establish. Ready to send/receive data", e)
  }

  onmessage(e) {
    this.route(JSON.parse(e.data))
  }

  onerror(e) {
    console.log("Unexpected error", e, "Will not re-connect")
  }

  register(editor, id) {
    this.editors[id] = editor

    return this
  }

  route(message) {
    const jobId = message.id || ""
      , snippetId = jobId.split('-')[0]

    if (snippetId != "" && this.editors[snippetId]) {
      this.editors[snippetId].onmessage(message, jobId)
    } else {
      for (const k in this.editors) {
        this.editors[k].onmessage(message)
      }
    }

    return this
  }
}

const e = React.createElement;
class CommandEditor extends React.Component {
  constructor(props) {
    super(props)

    this.props.runner.register(this, this.props.id)

    try {
      this.parseJobFromMarkdown()
    } catch (e) {
      alert("Invalid yaml config for job. Check runbook")
      console.log("Invalid yaml config for job. Check runbook", e)
    }
  }

  onmessage(message, jobId) {
    switch (message.type) {
      case "close":
        this.setState({...this.state, ready: false})
        break

      case "ready":
        this.free()
        break

      case "cmd:partial":
        const output = this.state.output
        output[jobId] = this.state.output[jobId] || ""
        output[jobId] += message.stdout

        this.setState({...this.state, output})
        break

      case "cmd:done":
        this.free()
        break

      case "cmd:start":
        this.busy()
        break

      default:
        console.log("Unkow message", message)
    }
  }

  free() {
    this.setState({...this.state, ready: true, running: false})
  }

  spin() {
    this.setState({...this.state, loading: true})
    this.busy()
  }

  busy() {
    this.setState({...this.state, ready: false, running: true})
  }

  parseJobFromMarkdown() {
    let [config, code] = this.props.runbook.split("---").map((e) => e.trim())

    console.log(config)
    console.log(code)
    if (code) {
      config = jsyaml.load(config)
    } else {
      code = config
      config = {}
    }

    this.state = {
      code: code,
      config: config,
      ready: false,
      running: false,
      output: {},
      input: {}
    }
  }

  onChangeInput(e) {
    const input = this.state.input
    input[e.target.placeholder] = e.target.value

    this.setState({...this.state, input})
  }

  onRun(e) {
    const uuid  = Math.random().toString(36).substring(2, 15)
    const jobId = `${this.props.id}-${uuid}`

    let inputs = ""
    if (this.state.config.input) {
      for (const p in this.state.input) {
        inputs += `export ${p}=${this.state.input[p]}`
      }

      inputs += "\n\n"
    }

    this.spin()
    this.props.runner.send({
      type: 'run',
      id: jobId,
      payload: inputs + this.codemirror.getValue(),
      config: this.state.config,
    })
  }

  render() {
    if (this.state.liked) {
      return 'You liked this.';
    }

    const paramControl = []
    if (this.state.config.input) {
      for (const p in this.state.config.input) {
        paramControl.push(e(
          "div",
          { key: `control-${p}`, className: "form-group" },
          e("label", { key: `label-${p}`, className: "form-label" }, e("h6", {}, this.state.config.input[p])),
          e("input", { key: `input-${p}`, className: "form-input", type: "text", placeholder: p, onChange: this.onChangeInput.bind(this)}),
        ))
      }
    }

    const buttonControl = e(
      "div",
      {className: "form-group"},
      e("button",
        {className: `run-job ${this.state.ready ? '': 'disabled'} ${this.state.running ? 'loading' : '' } btn btn-large btn-success p-centered`, onClick: this.onRun.bind(this)},
        e("i", {className: "icon icon-arrow-right"}),
        "Run"
      )
    )
    const outputControl = e(
      "div",
      {className: `job-output`, style: {"maxHeight": '1000px', overflow: "auto"} },
      Object.keys(this.state.output).map(job => e("pre",
          {key: job, "data-lang": "shell", className: "code"},
          e("code", {}, this.state.output[job])
        )
      ),
      e("div", {className: `this.state.loading ? "loading" : ''`})
    )

    const editorControl = e("textarea", {
      value: this.state.code,
      readOnly: true,
      ref: (ref) => { this.textarea = ref },
    })

    return e(
      "div",
      {},
      paramControl,
      editorControl,
      buttonControl,
      outputControl
    );
  }

  componentDidMount() {
    this.codemirror = CodeMirror.fromTextArea(this.textarea, {
      lineNumbers: true,
      viewportMargin: Infinity
    })
    this.codemirror.setSize("100%", 200)
  }
}

const runner = new JobRunner()
document.querySelectorAll('textarea').forEach((t, i) => {
  const content = t.value.trim()
  const appNode = document.createElement("div");
  t.parentNode.replaceChild(appNode, t)
  ReactDOM.render(e(CommandEditor, { runner: runner, id: i, runbook: content }), appNode)
})
runner.connect()
