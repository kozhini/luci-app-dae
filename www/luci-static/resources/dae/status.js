"require ui";
"require rpc";
"require baseclass";

const NAME = "dae";

var getInitStatus = rpc.declare({
	object: "luci." + NAME,
	method: "getInitStatus",
	params: ["name"],
});

var _setInitAction = rpc.declare({
	object: "luci." + NAME,
	method: "setInitAction",
	params: ["name", "action"],
	expect: { result: false },
});

var RPC = {
	listeners: [],
	on: function (event, callback) {
		var pair = { event: event, callback: callback };
		this.listeners.push(pair);
		return function unsubscribe() {
			this.listeners = this.listeners.filter(function (l) { return l !== pair; });
		}.bind(this);
	},
	emit: function (event, data) {
		this.listeners.forEach(function (l) {
			if (l.event === event) l.callback(data);
		});
	},
	setInitAction: function (name, action) {
		_setInitAction(name, action).then(function (result) {
			this.emit("setInitAction", { result: result, action: action });
		}.bind(this)).catch(function () {
			this.emit("setInitAction", { timeout: true, action: action });
		}.bind(this));
	},
};

// Poll until running state matches expectation
function pollServiceStatus(expectRunning, callback) {
	var maxAttempts = 60;
	var attempt = 0;
	function check() {
		attempt++;
		L.resolveDefault(getInitStatus(NAME), {}).then(function (data) {
			var running = (data && data[NAME] && data[NAME].running) === true;
			if (expectRunning ? running : !running) {
				callback(true);
			} else if (attempt >= maxAttempts) {
				callback(false);
			} else {
				setTimeout(check, 1000);
			}
		}).catch(function () {
			if (attempt < maxAttempts) setTimeout(check, 1000);
			else callback(false);
		});
	}
	setTimeout(check, 2000);
}

RPC.on("setInitAction", function (reply) {
	var action = reply && reply.action;
	if (action === "start" || action === "restart") {
		pollServiceStatus(true, function () {
			ui.hideModal();
			location.reload();
		});
	} else if (action === "stop") {
		pollServiceStatus(false, function () {
			ui.hideModal();
			location.reload();
		});
	} else {
		// enable/disable/reload_config: fast, reload immediately
		setTimeout(function () { ui.hideModal(); location.reload(); }, 1000);
	}
});

var statusWidget = baseclass.extend({
	render: function () {
		return L.resolveDefault(getInitStatus(NAME), {}).then(function (data) {
			var s = (data && data[NAME]) || { version: null, enabled: null, running: null };

			// ── Status ────────────────────────────────────────────────────
			var text = NAME + " ";
			text += s.version ? s.version : _("not installed or not found");

			var statusDiv = E("div", { class: "cbi-value" }, [
				E("label", { class: "cbi-value-title" }, _("Service Status")),
				E("div", { class: "cbi-value-field" }, [
					E("div", {}, text),
					E("div", {}, s.running
						? E("span", { style: "color:green" }, _("Running"))
						: E("span", { style: "color:red"  }, _("Inactive"))
					),
				]),
			]);

			// ── Update buttons (определяем до проверки версии) ───────────
			function startPolling(statusEl, btn, lockField, doneMsg) {
				statusEl.textContent = "\u23f3 " + _("Updating...");
				var timer = setInterval(function () {
					getInitStatus(NAME).then(function (d) {
						if (!((d && d[NAME]) || {})[lockField]) {
							clearInterval(timer);
							btn.disabled = false;
							if (lockField === "dae_updating") {
								statusEl.textContent = "\u2713 " + doneMsg + " \u2014 " + _("Reload the page to apply.");
							} else {
								statusEl.textContent = "\u2713 " + doneMsg;
								// Обновляем дату geo баз
								var st = (d && d[NAME]) || {};
								var ts = Math.min(st.geoip_mtime || 0, st.geosite_mtime || 0);
								if (ts && geoDateEl) {
									geoDateEl.textContent = _("Updated: %s").format(fmtDate(ts));
								}
								setTimeout(function () { statusEl.textContent = ""; }, 4000);
							}
						}
					});
				}, 2000);
			}

			function updBtn(label, action, lockField, active) {
				var statusEl = E("span", { style: "margin-left:8px;font-size:.85em;color:#888" }, "");
				var btn = E("button", {
					class: "btn cbi-button cbi-button-action",
					click: function () {
						btn.disabled = true;
						_setInitAction(NAME, action).then(function (res) {
							if (!res) {
								statusEl.textContent = "\u26a0 " + _("Already running");
								btn.disabled = false;
								return;
							}
							startPolling(statusEl, btn, lockField,
								action === "update" ? _("dae updated") : _("Geo databases updated"));
						});
					},
				}, [_(label)]);
				if (active) {
					btn.disabled = true;
					startPolling(statusEl, btn, lockField,
						action === "update" ? _("dae updated") : _("Geo databases updated"));
				}
				return E("span", {}, [btn, statusEl]);
			}

			function fmtDate(ts) {
				if (!ts || ts === 0) return _("never");
				var d = new Date(ts * 1000);
				return d.getFullYear() + "-" +
					String(d.getMonth()+1).padStart(2,"0") + "-" +
					String(d.getDate()).padStart(2,"0") + " " +
					String(d.getHours()).padStart(2,"0") + ":" +
					String(d.getMinutes()).padStart(2,"0");
			}

			var btn_gapl = E("span", {}, "\u00a0\u00a0\u00a0\u00a0\u00a0\u00a0\u00a0\u00a0");

			// Берём более раннюю из двух дат как время последнего обновления баз
			var geoTs = Math.min(s.geoip_mtime || 0, s.geosite_mtime || 0);
			var geoDateEl = E("span", {
				style: "margin-left:8px;font-size:.85em;color:#888"
			}, geoTs ? _("Updated: %s").format(fmtDate(geoTs)) : "");

			var updDiv = E("div", { class: "cbi-value" }, [
				E("label", { class: "cbi-value-title" }, _("Updates")),
				E("div", { class: "cbi-value-field" }, [
					updBtn("Update dae",           "update",     "dae_updating", s.dae_updating),
					btn_gapl,
					updBtn("Update Geo databases", "update_geo", "geo_updating", s.geo_updating),
					geoDateEl,
				]),
			]);

			if (!s.version) return E("div", {}, [statusDiv, updDiv]);

			// ── Service control ───────────────────────────────────────────
			var btn_gap = E("span", {}, "\u00a0\u00a0");

			var btn_start = E("button", {
				class: "btn cbi-button cbi-button-apply", disabled: true,
				click: function () {
					ui.showModal(null, [E("p", { class: "spinning" }, _("Starting %s...").format(NAME))]);
					RPC.setInitAction(NAME, "start");
				},
			}, [_("Start")]);

			var btn_restart = E("button", {
				class: "btn cbi-button cbi-button-apply", disabled: true,
				click: function () {
					ui.showModal(null, [E("p", { class: "spinning" }, _("Restarting %s...").format(NAME))]);
					RPC.setInitAction(NAME, "restart");
				},
			}, [_("Restart")]);

			var btn_stop = E("button", {
				class: "btn cbi-button cbi-button-reset", disabled: true,
				click: function () {
					ui.showModal(null, [E("p", { class: "spinning" }, _("Stopping %s...").format(NAME))]);
					RPC.setInitAction(NAME, "stop");
				},
			}, [_("Stop")]);

			var btn_enable = E("button", {
				class: "btn cbi-button cbi-button-apply", disabled: true,
				click: function () {
					ui.showModal(null, [E("p", { class: "spinning" }, _("Enabling %s...").format(NAME))]);
					RPC.setInitAction(NAME, "enable");
				},
			}, [_("Enable")]);

			var btn_disable = E("button", {
				class: "btn cbi-button cbi-button-reset", disabled: true,
				click: function () {
					ui.showModal(null, [E("p", { class: "spinning" }, _("Disabling %s...").format(NAME))]);
					RPC.setInitAction(NAME, "disable");
				},
			}, [_("Disable")]);

			// enabled/disabled влияет только на кнопки Enable/Disable
			// Start/Restart/Stop управляются только по running
			btn_enable.disabled  = !!s.enabled;
			btn_disable.disabled = !s.enabled;
			btn_start.disabled   = !!s.running;
			btn_restart.disabled = false;
			btn_stop.disabled    = !s.running;

			var ctrlDiv = E("div", { class: "cbi-value" }, [
				E("label", { class: "cbi-value-title" }, _("Service Control")),
				E("div", { class: "cbi-value-field" }, [
					btn_start, btn_gap,
					btn_restart, btn_gap,
					btn_stop, btn_gapl,
					btn_enable, btn_gap,
					btn_disable,
				]),
			]);

			return E("div", {}, [statusDiv, ctrlDiv, updDiv]);
		});
	},
});

return L.Class.extend({
	getStatus: statusWidget,
});
