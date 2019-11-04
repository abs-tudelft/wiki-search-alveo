import Vue from "vue";
import vuetify from "./plugins/vuetify";

import App from "./App.vue";

new Vue({ vuetify, render: h => h(App) }).$mount("#app");
