<template>
  <v-app>
    <v-content>
      <v-container>
        <!-- query input -->
        <v-row justify="center">
          <v-col cols="9">
            <v-text-field
              ref="query"
              class="display-3 text--primary"
              single-line
              v-model.trim="query"
              placeholder="Type a query"
              v-on:keyup.enter="getQuery"
              autofocus
              :loading="loading"
            ></v-text-field>
          </v-col>
        </v-row>

        <!-- configuration and clear/search -->
        <v-row justify="center">
          <!-- configuration panel -->
          <v-col cols="6">
            <v-expansion-panels v-model="configuration.open">
              <v-expansion-panel>
                <v-expansion-panel-header v-slot="{ open }">
                  <v-row no-gutters>
                    <v-fade-transition leave-absolute>
                      <span v-if="open"
                        ><v-icon>mdi-tune</v-icon> Configuration</span
                      >
                      <v-row v-else no-gutters style="width: 100%">
                        <v-col
                          v-if="configuration.whole_words"
                          align-self="center"
                          cols="4"
                          class="text--secondary"
                          >Match whole words</v-col
                        >
                        <v-col
                          v-else
                          align-self="center"
                          cols="4"
                          class="text--secondary"
                          >Normal match</v-col
                        >
                        <v-col
                          align-self="center"
                          cols="4"
                          class="text--secondary"
                          >≥ {{configuration.min_matches}} match<span v-if="configuration.min_matches!=1">es</span> per page</v-col
                        >
                        <v-col
                          v-if="configuration.software"
                          align-self="center"
                          cols="4"
                          class="text--secondary"
                          >Use {{configuration.num_threads}} CPU thread<span v-if="configuration.num_threads!=1">s</span></v-col
                        >
                        <v-col
                          v-else
                          align-self="center"
                          cols="4"
                          class="text--secondary"
                          >Use Alveo</v-col
                        >
                      </v-row>
                    </v-fade-transition>
                  </v-row>
                </v-expansion-panel-header>

                <!-- Configuration modifications -->
                <v-expansion-panel-content>
                  <v-row no-gutters align="center" justify="center">
                    <v-col offset="1" align-self="left" cols="5">
                      <v-row no-gutters align="left" justify="left">
                        <v-switch
                          v-model="configuration.whole_words"
                          label="Whole words"
                          inset
                          color="primary"
                        ></v-switch>
                      </v-row>
                      <v-row no-gutters align="left" justify="left">
                        <v-switch
                          v-model="configuration.software"
                          label="Run on CPU"
                          inset
                          color="primary"
                        ></v-switch>
                      </v-row>
                    </v-col>
                    <v-col align-self="center" cols="6">
                      <v-row
                        no-gutters
                        align="center"
                        justify="center"
                        class="text--secondary"
                      >
                        Minimum number of matches: {{configuration.min_matches}}
                      </v-row>
                      <v-row no-gutters
                      align="center"
                        justify="center">
                        <v-slider
                          min="1"
                          v-model="configuration.min_matches"
                          thumb-label
                        ></v-slider>
                      </v-row>
                      <v-row
                        no-gutters
                        align="center"
                        justify="center"
                        class="text--secondary"
                      >
                        Number of CPU threads: {{configuration.num_threads}}
                      </v-row>
                      <v-row no-gutters
                      align="center"
                        justify="center">
                        <v-slider
                          min="1"
                          max="40"
                          :disabled="!configuration.software"
                          v-model="configuration.num_threads"
                          thumb-label
                        ></v-slider>
                      </v-row>
                    </v-col>
                  </v-row>
                </v-expansion-panel-content>
              </v-expansion-panel>
            </v-expansion-panels>
          </v-col>
          <v-col self-align="center" cols="3">
            <v-btn
              color="warning"
              @click="clear"
              outlined
              x-large
              :disabled="query === undefined && response === undefined"
              >Clear</v-btn
            >
            <v-btn
              color="success"
              @click="getQuery"
              outlined
              x-large
              :disabled="query === undefined || loading === true"
              >Search</v-btn
            >
          </v-col>
        </v-row>
        <v-row>
          <v-divider></v-divider>
        </v-row>
      </v-container>

      <v-container v-if="response">
        <v-row v-if="response && response.results && response.results[0]">
          <v-col cols="5">
            <v-card outlined>
              <v-img
                class="align-end"
                :src="'wiki_img?article=' + response.results[0][0]"
              >
                <v-card-title class="headline">{{
                  response.results[0][0]
                }}</v-card-title>
              </v-img>
              <v-card-subtitle class="overline">TOP RESULT</v-card-subtitle>
              <v-card-actions>
                <!-- <v-btn text color="orange darken-4">{{ response.results[0][0] }}</v-btn> -->
                <v-spacer></v-spacer>
                <v-chip>{{ response.results[0][1] }}</v-chip>
              </v-card-actions>
            </v-card>
          </v-col>
        </v-row>
        <!-- <v-row>
          <v-expansion-panels v-if="result && result.results" accordion>
            <v-expansion-panel v-for="result in result.results">
              <v-expansion-panel-header>
                {{ result[0] }}
                <template v-slot:actions>
                  <v-chip color="primary">{{ result[1] }}</v-chip>
                </template>
              </v-expansion-panel-header>
              <v-expansion-panel-content> </v-expansion-panel-content>
            </v-expansion-panel>
          </v-expansion-panels>
        </v-row> -->
        <v-row v-if="response && response.stats">
          <v-alert outlined color="primary" v-if="!loading && response.query">
            <p>{{ response }}</p>
          </v-alert>
        </v-row>
        <!-- <v-list disabled
          v-if="result"
          v-for="result in result.results"
        >
          <v-list-item>
            <v-badge>
              {{ result[0] }}
              <template v-slot:badge>{{ result[1] }}</template>
            </v-badge>
          </v-list-item>
        </v-list>
 -->
      </v-container>
    </v-content>

    <v-footer class="grey lighten-3">
      <v-container>
        <v-row align="center" justify="center">
          <v-col align="center" justify="center" cols="2">
            <img src="../assets/xilinx-logo.svg" height="100px" />
          </v-col>
          <v-col align="center" justify="center" cols="2">
            <img
              src="https://repository-images.githubusercontent.com/120948886/c0dcc400-80aa-11e9-8a51-c7ff5364fe0a"
              height="70px"
            />
          </v-col>
          <v-col align="center" justify="center" cols="2">
            <img src="../assets/tudelft-logo.svg" height="50px" />
          </v-col>
          <v-col align="center" justify="center" cols="2">
            <img src="../assets/wikipedia-logo.svg" height="50px" />
          </v-col>
        </v-row>
      </v-container>
    </v-footer>
  </v-app>
</template>

<script>
import Vue from "vue";

export default Vue.extend({
  data() {
    return {
      configuration: {
        open: false,
        whole_words: false,
        min_matches: 1,
        software: false,
        num_threads: 40
      },
      query: undefined,
      response: undefined,
      loading: false
    };
  },
  methods: {
    clear: function() {
      this.query = undefined;
      this.loading = false;
      this.response = undefined;
      this.$refs.query.focus();
    },
    getQuery: function() {
      if (this.loading) {
        return;
      }
      if (!this.query || this.query === "") {
        return;
      }
      var mode = this.configuration.software ? this.configuration.num_threads : 0;
      this.loading = true;
      this.response = undefined;
      this.configuration.open = false;
      fetch(
        `query?pattern=${this.query}&whole_words=${this.configuration.whole_words}&min_matches=${this.configuration.min_matches}&mode=${mode}`
      ).then(res => res.json()).then(res => {
        if (this.loading) {
          this.loading = false;
          this.response = res;
        }
      })
    }
  }
});
</script>

<style>
.v-input input {
  max-height: 900em;
}
.v-expansion-panel::before {
  box-shadow: none;
}
</style>
