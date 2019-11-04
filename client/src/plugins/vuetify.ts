import "@mdi/font/css/materialdesignicons.css";
import Vue from "vue";
import Vuetify, {
  VApp,
  VChip,
  VSpacer,
  VIcon,
  VBtn,
  VRow,
  VContent,
  VImg,
  VContainer,
  VCard,
  VCardTitle,
  VCardActions,
  VCardText,
  VCardSubtitle,
  VDataTable,
  VForm,
  VRating,
  VToolbar,
  VTextField,
  VSkeletonLoader,
  VExpansionPanels,
  VExpansionPanel,
  VExpansionPanelHeader,
  VExpansionPanelContent,
  VSwitch,
  VBtnToggle,
  VSlider,
  VSubHeader,
  VList,
  VListItem,
  VListItemGroup,
  VListItemContent,
  VListItemIcon,
  VDivider,
  VCol,
  VProgressLinear,
  VFooter,
  VAlert,
  VBadge,
  VFadeTransition
} from "vuetify/lib";
import { Ripple } from "vuetify/lib/directives";
import colors from "vuetify/lib/util/colors";

Vue.use(Vuetify, {
  components: {
    VApp,
    VImg,
    VSpacer,
    VChip,
    VIcon,
    VBtn,
    VRow,
    VContent,
    VContainer,
    VCardTitle,
    VCardText,
    VCardSubtitle,
    VCard,
    VCardActions,
    VForm,
    VRating,
    VToolbar,
    VTextField,
    VSkeletonLoader,
    VExpansionPanels,
    VExpansionPanel,
    VExpansionPanelHeader,
    VExpansionPanelContent,
    VSwitch,
    VBtnToggle,
    VSlider,
    VSubHeader,
    VList,
    VListItem,
    VListItemGroup,
    VListItemContent,
    VListItemIcon,
    VDivider,
    VCol,
    VProgressLinear,
    VDataTable,
    VFooter,
    VAlert,
    VBadge,
    VFadeTransition
  },
  directives: {
    Ripple
  }
});

const opts = {
  icons: {
    iconfont: "mdi" // 'mdi' || 'mdiSvg' || 'md' || 'fa' || 'fa4'
  },
  theme: {
    themes: {
      light: {
        primary: {
          base: colors.indigo.base,
          darken1: colors.indigo.darken2
        },
        secondary: colors.indigo,
        tertiary: colors.pink.base
      }
    },
    dark: false
  }
};

export default new Vuetify(opts);
