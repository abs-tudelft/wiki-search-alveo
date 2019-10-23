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

      <!--<v-container v-if="!response && !loading">
        <v-row justify="center">
          <v-col cols="9">
            <p style="font-size: 1.2em; text-align: justify; text-align-last: center">
              Type a query above to search a Wikipedia database dump for a word or
              part of a word,<br/><span class="font-weight-bold">without an index</span>.
            </p>
            <p style="text-align: justify; text-align-last: center">
              The database dump was pre-downloaded and transformed into
              <span class="font-weight-bold">Apache Arrow</span> IPC format using
              <span class="font-weight-bold">Apache Spark</span>. To make things a bit
              more interesting, the article text is compressed with
              <span class="font-weight-bold">Google Snappy</span> - the default
              compression format of <span class="font-weight-bold">Apache Parquet</span>.
              The resulting dataset is about 22GB in size for the English Wikipedia
              without meta pages. The dataset is cached onto the local DDR banks of a
              <span class="font-weight-bold">Xilinx Alveo U200</span> FPGA accelerator
              card. The FPGA design consists of 45 RTL Snappy decompression engines
              and pattern matchers, fed with streaming Arrow data through a
              <span class="font-weight-bold">Fletcher</span> interface, and integrated
              with <span class="font-weight-bold">SDAccel</span>. For comparison, the
              algorithm can also be run on CPU, using up to forty Intel Xeon Silver
              4114 processor threads.
            </p>
          </v-col>
        </v-row>
      </v-container>-->

      <v-container v-if="response || loading">
        <v-row justify="center">
          <v-col cols="4">
            <v-row align="center">
              <v-col cols=2>
                Alveo
              </v-col>
              <v-col cols=6>
                <v-progress-linear
                  :value="hw_time / 200"
                  color="light-blue"
                  height="16px"
                  style="transition-duration: 0s"
                />
              </v-col>
              <v-col cols=4>
                {{hw_time}} ms
              </v-col>
            </v-row>
            <v-row align="center">
              <v-col cols=2>
                CPU
              </v-col>
              <v-col cols=6>
                <v-progress-linear
                  :value="sw_time / 200"
                  color="orange"
                  height="16px"
                  style="transition-duration: 0s"
                />
              </v-col>
              <v-col cols=4>
                {{sw_time}} ms
              </v-col>
            </v-row>
            <v-row align="center">
              <v-col cols=2>
              </v-col>
              <v-col cols=6 style="text-align: center">
                <span v-if="!loading">Done! Alveo speedup: {{Number((sw_time / hw_time).toFixed(2))}}x</span>
                <span v-if="loading && configuration.software">Running on CPU...</span>
                <span v-if="loading && !configuration.software">Running on Alveo...</span>
              </v-col>
              <v-col cols=4>
              </v-col>
            </v-row>
          </v-col>
          <v-col cols="4">
            <p style="font-size: 1.2em; text-align: justify; text-align-last: right" v-if="response">
              <span class="font-weight-bold">{{response.stats.num_word_matches}}</span>
              word<span v-if="response.stats.num_word_matches!=1">s</span>
              matched across
              <span class="font-weight-bold">{{response.stats.num_page_matches}}</span>
              page<span v-if="response.stats.num_page_matches!=1">s</span>,<br/>
              of which
              <span v-if="response.stats.num_result_records!=response.stats.num_page_matches">
                only <span class="font-weight-bold">{{response.stats.num_result_records}}</span>
                page match<span v-if="response.stats.num_result_records!=1">es were</span>
                <span v-else>was</span>
              </span>
              <span v-else>
                all page matches were
              </span>
              recorded and sorted.
            </p>
            <p style="text-align: justify; text-align-last: right" v-if="response">
              The query took
              <span class="font-weight-bold">{{response.stats.time_taken_ms}} ms</span>,
              making the equivalent<br/>compressed article text bandwidth approximately
              <span class="font-weight-bold">{{response.stats.bandwidth}}</span>.
            </p>
          </v-col>
        </v-row>
      </v-container>

      <v-container v-if="response">
        <v-row>
          <v-divider></v-divider>
        </v-row>
        <v-row v-if="response.top_result" justify="center">
          <v-col cols="6">
            <v-card outlined>
              <v-img
                class="align-end"
                :src="'wiki_img?article=' + response.top_result[0]"
                height="400px"
                gradient="to bottom, rgba(0,0,0,.05), rgba(0,0,0,.3)"
              >
                <v-card-title class="headline white--text">{{
                  response.top_result[0]
                }}</v-card-title>
              </v-img>
              <v-card-subtitle class="overline">TOP RESULT</v-card-subtitle>
              <v-card-actions>
                <!-- <v-btn text color="orange darken-4">{{ response.top_result[0] }}</v-btn> -->
                <v-spacer></v-spacer>
                <v-chip>{{ response.top_result[1] }}</v-chip>
              </v-card-actions>
            </v-card>
          </v-col>
        </v-row>
        <v-row justify="center">
          <v-col cols="9">
            <v-row v-if="response.top_result && response.top_ten_results" justify="center" dense>
              <v-col cols="4" v-for="(result, idx) in response.top_ten_results">
                <v-card outlined>
                  <v-img
                    class="align-end"
                    :src="'wiki_img?article=' + result[0]"
                    height="200px"
                    gradient="to bottom, rgba(0,0,0,.05), rgba(0,0,0,.3)"
                  >
                    <v-card-title class="headline white--text">{{
                      result[0]
                    }}</v-card-title>
                  </v-img>
                  <v-card-subtitle class="overline">RESULT #{{idx + 2}}</v-card-subtitle>
                  <v-card-actions>
                    <!-- <v-btn text color="orange darken-4">{{ result[0] }}</v-btn> -->
                    <v-spacer></v-spacer>
                    <v-chip>{{ result[1] }}</v-chip>
                  </v-card-actions>
                </v-card>
              </v-col>
            </v-row>
          </v-col>
        </v-row>
        <v-row v-if="response.top_result && response.other_results">
          <v-divider></v-divider>
        </v-row>
        <v-row v-if="response.top_result && response.other_results && response.top_ten_results.length == 0" justify="center">
          <v-col cols="5">
            <p style="text-align: justify; text-align-last: center">
              Note: kernel result slots overflowed. The matches shown here are a random
              sample of the pages that matched; there may be pages with more matches.
            </p>
          </v-col>
        </v-row>
        <v-row v-if="response.top_result && response.other_results" justify="center">
          <v-col cols="4">
            <v-list disabled dense>
              <v-list-item v-for="(result, idx) in response.other_results">
                <v-list-item-content>
                  <v-list-item-title>
                    <span
                      v-if="response.top_ten_results.length != 0"
                      class="text--secondary"
                    >
                      #{{response.top_ten_results.length + idx + 2}}
                    </span>
                    {{result[0]}}
                  </v-list-item-title>
                </v-list-item-content>
                <v-list-item-avatar>
                  <v-chip>{{result[1]}}</v-chip>
                </v-list-item-avatar>
              </v-list-item>
            </v-list>
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
        <!--<v-row v-if="response && response.stats">
          <v-alert outlined color="primary" v-if="!loading && response.query">
            <p>{{ response }}</p>
          </v-alert>
        </v-row>-->
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
      loading: false,
      timer: undefined,
      sw_time: 0,
      hw_time: 0
    };
  },
  methods: {
    clear: function() {
      this.query = undefined;
      this.loading = false;
      this.response = undefined;
      clearInterval(this.timer);
      this.sw_time = 0;
      this.hw_time = 0;
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
      if (this.configuration.software) {
        this.sw_time = 0;
      } else {
//        this.sw_time = 0;
        this.hw_time = 0;
      }
      this.timer = setInterval(() => {
        if (this.configuration.software) {
          this.sw_time += 50;
        } else {
          this.hw_time += 50;
        }
      }, 50)
      fetch(
        `query?pattern=${this.query}&whole_words=${this.configuration.whole_words}&min_matches=${this.configuration.min_matches}&mode=${mode}`
      ).then(res => res.json()).then(res => {
        if (this.loading) {
          this.loading = false;
          this.response = res;
          if (this.configuration.software) {
            this.sw_time = res.stats.time_taken_ms;
          } else {
            this.hw_time = res.stats.time_taken_ms;
          }
          clearInterval(this.timer);
//           if (!this.configuration.software) {
//             this.configuration.software = true;
//             this.getQuery();
//           } else {
//             this.configuration.software = false;
//           }
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
